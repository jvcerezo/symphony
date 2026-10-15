import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide AudioStreamInfo;
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';
import '../../../../core/config/server_config.dart';
import 'extraction/audio_extractor.dart';
import 'extraction/platform_audio_extractor.dart';
import 'matching/match_index.dart';
import 'offline/local_track_store.dart';

class AudioStreamResolverService {
  final YoutubeExplode _yt;
  final AudioExtractor _extractor;
  final http.Client _httpClient;
  final LocalTrackStore _localTracks;
  final MatchIndex _matchIndex;
  final bool _isWeb;

  /// In-memory resolution cache keyed by track ID and normalized artist/title.
  final Map<String, ResolvedAudioStream> _resolvedCache = {};

  /// In-flight futures to coalesce simultaneous resolve requests for the same track.
  final Map<String, Future<ResolvedAudioStream>> _inFlightResolutions = {};

  /// Resolves the user is waiting on; background prefetching pauses for them.
  int _foregroundResolves = 0;
  final List<Track> _prefetchQueue = [];
  bool _prefetchRunning = false;
  static const _maxPrefetchQueue = 12;

  factory AudioStreamResolverService({
    YoutubeExplode? ytClient,
    AudioExtractor? extractor,
    http.Client? httpClient,
    LocalTrackStore? localTracks,
    MatchIndex? matchIndex,
    @visibleForTesting bool? isWeb,
  }) {
    final yt = ytClient ?? YoutubeExplode();
    return AudioStreamResolverService._(
      yt,
      extractor ?? createPlatformAudioExtractor(yt),
      httpClient: httpClient,
      localTracks: localTracks,
      matchIndex: matchIndex,
      isWeb: isWeb,
    );
  }

  AudioStreamResolverService._(
    this._yt,
    this._extractor, {
    http.Client? httpClient,
    LocalTrackStore? localTracks,
    MatchIndex? matchIndex,
    bool? isWeb,
  })  : _matchIndex = matchIndex ?? MatchIndex.platform(),
        _httpClient = httpClient ?? http.Client(),
        _localTracks = localTracks ?? LocalTrackStore.platform(),
        _isWeb = isWeb ?? kIsWeb;

  /// On-device downloads consulted before any network resolution (non-web).
  LocalTrackStore get localTracks => _localTracks;

  String _normKey(Track track) =>
      '${_cleanSongArtist(track.artist).toLowerCase()} - ${_cleanSongTitle(track.title).toLowerCase()}';

  /// Returns the cached stream if available (0ms instant lookup).
  ResolvedAudioStream? getCachedStream(Track track) {
    final primaryKey = track.id;
    final normKey = _normKey(track);
    return _resolvedCache[primaryKey] ?? _resolvedCache[normKey];
  }

  /// Whether a track has already been resolved into memory.
  bool isTrackResolved(Track track) => getCachedStream(track) != null;

  /// Cache a stream manually (e.g. for pre-seeded tracks).
  void cacheResolvedStream(String key, ResolvedAudioStream stream) {
    _resolvedCache[key] = stream;
  }

  /// Resolves a track in the background (yielding to anything the user is
  /// waiting on) without throwing.
  Future<ResolvedAudioStream?> preloadTrack(Track track) async {
    if (isTrackResolved(track)) {
      return getCachedStream(track);
    }
    try {
      final stream = await _resolveShared(track);
      developer.log('Preloaded stream for: "${track.title}" -> ${stream.streamUri}', name: 'AudioStreamResolver');
      return stream;
    } catch (e) {
      developer.log('Preload error for "${track.title}": $e', name: 'AudioStreamResolver');
      return null;
    }
  }

  /// Proactively preloads upcoming tracks sequentially in the background.
  /// Native: queued for [prefetch] (newest request first).
  void preloadTracks(List<Track> tracks, {int count = 2}) {
    if (tracks.isEmpty) return;
    if (!_isWeb) {
      prefetch(tracks.take(count), replace: true);
      return;
    }
    Future.microtask(() async {
      for (final track in tracks.take(count)) {
        if (!isTrackResolved(track)) {
          await preloadTrack(track);
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }
    });
  }

  /// Resolves [tracks] in the background so tapping them later plays at once:
  /// one at a time, pausing whenever the user is waiting on a resolve, and
  /// skipping tracks that already have a local file or a fresh stream link.
  /// With [replace], anything still queued is dropped first.
  void prefetch(Iterable<Track> tracks, {bool replace = false}) {
    if (_isWeb) return;
    if (replace) _prefetchQueue.clear();
    for (final t in tracks) {
      final key = _normKey(t);
      if (_prefetchQueue.every((q) => _normKey(q) != key)) _prefetchQueue.add(t);
    }
    if (_prefetchQueue.length > _maxPrefetchQueue) {
      _prefetchQueue.removeRange(_maxPrefetchQueue, _prefetchQueue.length);
    }
    if (!_prefetchRunning) unawaited(_runPrefetch());
  }

  Future<void> _runPrefetch() async {
    _prefetchRunning = true;
    try {
      while (_prefetchQueue.isNotEmpty) {
        while (_foregroundResolves > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        final track = _prefetchQueue.removeAt(0);
        if (await hasInstantSource(track)) continue;
        try {
          await _resolveShared(track);
        } catch (e) {
          developer.log('Prefetch failed for "${track.title}": $e', name: 'AudioStreamResolver');
        }
      }
    } finally {
      _prefetchRunning = false;
    }
  }

  /// Whether [track] can start without running yt-dlp: a downloaded file, an
  /// unexpired in-memory stream, or a fresh remembered link.
  Future<bool> hasInstantSource(Track track) async {
    if (await resolveLocal(track) != null) return true;
    final cached = getCachedStream(track);
    if (cached != null && !_isExpired(cached)) return true;
    if (_isWeb) return false;
    final remembered = await _matchIndex.lookup(_normKey(track));
    return remembered != null && remembered.isTrusted && remembered.hasFreshLink;
  }

  static bool _isExpired(ResolvedAudioStream stream) {
    final expiry = MatchEntry.expiryOf(stream.streamUri);
    return expiry != null && !expiry.isAfter(DateTime.now().add(MatchEntry.expiryMargin));
  }

  /// Clears in-memory resolution cache.
  void clearCache() {
    _resolvedCache.clear();
    _inFlightResolutions.clear();
  }

  /// Resolves a playable full-length audio stream for a [Track].
  ///
  /// On Web (`kIsWeb`), queries the backend `/api/resolve` service running
  /// in Symphony's pure Dart HTTP server to extract full master YouTube audio
  /// without browser CORS limitations and with full Range/seeking support.
  /// On Native, extracts on-device YouTube streams via `youtube_explode_dart`,
  /// falling back to the global CDN if YouTube blocks or restricts the device.
  ///
  /// Order: on-device download (non-web only) → in-memory cache → in-flight
  /// request → network resolution. Local hits are never put in the memory
  /// cache so deleting a download takes effect immediately.
  Future<ResolvedAudioStream> resolveBestAudioStream(Track track) async {
    _foregroundResolves++;
    try {
      return await _resolveShared(track);
    } finally {
      _foregroundResolves--;
    }
  }

  Future<ResolvedAudioStream> _resolveShared(Track track) async {
    final local = await resolveLocal(track);
    if (local != null) return local;

    final primaryKey = track.id;
    final normKey = _normKey(track);

    // 0. Cache hit - 0ms instant playback! (unless the link has expired)
    final cached = _resolvedCache[primaryKey] ?? _resolvedCache[normKey];
    if (cached != null && !_isExpired(cached)) {
      developer.log('Instant cache hit for "${track.title}"', name: 'AudioStreamResolver');
      return cached;
    }
    if (cached != null) forgetTrack(track);

    // 1. In-flight request deduplication
    if (_inFlightResolutions.containsKey(primaryKey)) {
      return await _inFlightResolutions[primaryKey]!;
    }
    if (_inFlightResolutions.containsKey(normKey)) {
      return await _inFlightResolutions[normKey]!;
    }

    final future = _doResolveBestAudioStream(track);
    _inFlightResolutions[primaryKey] = future;
    _inFlightResolutions[normKey] = future;

    try {
      final resolved = await future;
      _resolvedCache[primaryKey] = resolved;
      _resolvedCache[normKey] = resolved;
      if (resolved.sourceVideoId.isNotEmpty) {
        _resolvedCache['vid_${resolved.sourceVideoId}'] = resolved;
        _resolvedCache[resolved.sourceVideoId] = resolved;
      }
      return resolved;
    } finally {
      _inFlightResolutions.remove(primaryKey);
      _inFlightResolutions.remove(normKey);
    }
  }

  /// The downloaded file for [track] as a `file://` stream, or null (always
  /// null on web or if the local index can't be read).
  Future<ResolvedAudioStream?> resolveLocal(Track track) async {
    if (_isWeb || !_localTracks.isSupported) return null;
    try {
      final entry = await _localTracks.lookup(track);
      if (entry == null) return null;
      developer.log('On-device file for "${track.title}" -> ${entry.fileUri}', name: 'AudioStreamResolver');
      final seconds = entry.duration.inSeconds;
      return ResolvedAudioStream(
        streamUri: entry.fileUri,
        duration: entry.duration > Duration.zero ? entry.duration : (track.expectedDuration ?? Duration.zero),
        bitrateKbps: seconds > 0 ? (entry.bytes * 8 / 1000 / seconds).round() : 0,
        format: entry.format,
        sourceVideoId: entry.sourceVideoId,
      );
    } catch (e) {
      developer.log('Local lookup failed for "${track.title}": $e', name: 'AudioStreamResolver');
      return null;
    }
  }

  Future<ResolvedAudioStream> _doResolveBestAudioStream(Track track) async {
    // 0. Direct full stream attached to track (e.g. pre-seeded master streams or local files)
    if (track.streamUri != null && !_isShortPreviewStream(track.streamUri)) {
      developer.log(
        'Direct full streamUri playback for: "${track.title}" -> ${track.streamUri}',
        name: 'AudioStreamResolver',
      );
      return ResolvedAudioStream(
        streamUri: track.streamUri!,
        duration: track.expectedDuration ?? Duration.zero,
        bitrateKbps: 320,
        format: track.streamUri!.path.endsWith('.m4a') ? 'aac' : 'mp3',
        sourceVideoId: track.id,
      );
    }

    final knownVideoId = track.id.startsWith('yt_') ? track.id.replaceFirst('yt_', '') : null;

    // Web cannot extract in the browser, so it asks the Symphony server.
    if (_isWeb) {
      final serverResolved = await resolveViaWebServer(track, videoId: knownVideoId);
      if (serverResolved != null) return serverResolved;
      throw AudioStreamResolutionException(
        'Could not resolve a playable audio stream for "${track.title}" by "${track.artist}"',
      );
    }

    // Native: everything below runs on this device. No Symphony server.
    final matchKey = _normKey(track);
    final remembered = await _matchIndex.lookup(matchKey);

    // 0. A still-valid stream link from an earlier resolve: no yt-dlp at all.
    if (remembered != null && remembered.isTrusted && remembered.hasFreshLink) {
      developer.log('Fresh remembered link for "${track.title}"', name: 'AudioStreamResolver');
      return ResolvedAudioStream(
        streamUri: remembered.url!,
        duration: remembered.durationMs != null
            ? Duration(milliseconds: remembered.durationMs!)
            : (track.expectedDuration ?? Duration.zero),
        bitrateKbps: 0,
        format: remembered.container ?? 'm4a',
        sourceVideoId: remembered.videoId,
      );
    }

    // 1. Known YouTube video id (e.g. YouTube-imported playlists)
    if (knownVideoId != null) {
      try {
        final resolved = await _extractOnDevice(knownVideoId, fallbackDuration: track.expectedDuration);
        await _rememberResolved(matchKey, resolved, MatchSource.videoId);
        return resolved;
      } catch (e) {
        developer.log('On-device extraction failed for $knownVideoId: $e', name: 'AudioStreamResolver');
      }
    }

    // 2. A video this track matched before (survives app restarts and cache
    //    eviction). Older saves go through song search first, once.
    Future<ResolvedAudioStream?> replayRemembered(MatchEntry entry) async {
      try {
        final resolved = await _extractOnDevice(entry.videoId, fallbackDuration: track.expectedDuration);
        await _rememberResolved(matchKey, resolved, entry.source ?? MatchSource.scoredSearch);
        return resolved;
      } catch (e) {
        developer.log('Remembered match ${entry.videoId} failed, searching again: $e', name: 'AudioStreamResolver');
        await _matchIndex.forget(matchKey);
        return null;
      }
    }

    if (remembered != null && remembered.isTrusted) {
      final resolved = await replayRemembered(remembered);
      if (resolved != null) return resolved;
    }

    final cleanTitle = _cleanSongTitle(track.title);
    final cleanArtist = _cleanSongArtist(track.artist);

    // 3. YouTube Music song search: canonical album audio (lengths match the
    //    streaming services) found and extracted in a single yt-dlp run.
    try {
      final resolved = await _searchSongMatch(track);
      if (resolved != null) {
        if (remembered != null && remembered.videoId != resolved.sourceVideoId) {
          developer.log('Replacing old match ${remembered.videoId} for "${track.title}" with ${resolved.sourceVideoId}',
              name: 'AudioStreamResolver');
        }
        await _rememberResolved(matchKey, resolved, MatchSource.songSearch);
        return resolved;
      }
    } on UnsupportedError {
      // No song search on this extractor chain; fall through.
    } catch (e) {
      developer.log('Song search failed for "$cleanArtist - $cleanTitle": $e', name: 'AudioStreamResolver');
    }

    // An older save that song search couldn't improve on: keep it.
    if (remembered != null && !remembered.isTrusted) {
      final resolved = await replayRemembered(remembered);
      if (resolved != null) return resolved;
    }

    // 4. Search YouTube on-device, score candidates, extract the best match
    final queries = [
      '$cleanArtist $cleanTitle topic',
      '$cleanArtist - $cleanTitle official audio',
      '$cleanArtist - $cleanTitle',
      '$cleanTitle $cleanArtist',
    ];
    developer.log('Resolving full YouTube audio via client for: "$cleanArtist - $cleanTitle"', name: 'AudioStreamResolver');

    try {
      final seenVideoIds = <String>{};
      final scoredCandidates = <({Video video, int score})>[];

      for (final q in queries) {
        try {
          final searchResults = await _yt.search.search(q);
          for (final v in searchResults.take(6)) {
            if (v.isLive) continue;
            if (seenVideoIds.add(v.id.value)) {
              final sc = scoreVideoCandidate(
                videoTitle: v.title,
                videoAuthor: v.author,
                durationSec: v.duration?.inSeconds ?? 0,
                targetTitle: track.title,
                targetArtist: track.artist,
                expectedDurationMs: track.expectedDuration?.inMilliseconds,
              );
              if (sc > 0) {
                scoredCandidates.add((video: v, score: sc));
              }
            }
          }
          final expectedSecForExit = track.expectedDuration?.inSeconds;
          if (scoredCandidates.any((c) =>
              c.score >= 150 &&
              (expectedSecForExit == null ||
                  ((c.video.duration?.inSeconds ?? 0) - expectedSecForExit).abs() <= 5))) {
            break;
          }
        } catch (_) {}
      }

      if (scoredCandidates.isNotEmpty) {
        scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

        for (final scored in scoredCandidates.where((c) => c.score >= 50)) {
          final candidate = scored.video;
          try {
            final resolved = await _extractOnDevice(
              candidate.id.value,
              fallbackDuration: candidate.duration ?? track.expectedDuration,
            );
            await _rememberResolved(matchKey, resolved, MatchSource.scoredSearch);
            developer.log(
              'Resolved on-device via ${_extractor.name}: ${candidate.id.value} [${resolved.bitrateKbps} kbps, ${resolved.format}, score: ${scored.score}]',
              name: 'AudioStreamResolver',
            );
            return resolved;
          } catch (e) {
            developer.log('Candidate ${candidate.id.value} extraction failed: $e', name: 'AudioStreamResolver');
            continue;
          }
        }
      }
    } catch (e) {
      developer.log('On-device search failed: $e', name: 'AudioStreamResolver');
    }

    throw AudioStreamResolutionException(
      'Could not resolve a playable audio stream for "${track.title}" by "${track.artist}"',
    );
  }

  /// YouTube Music song search for [track]: its album recording, already
  /// extracted, or null when the top result isn't it. Throws when the search
  /// can't run (no song search on this platform, offline).
  Future<ResolvedAudioStream?> _searchSongMatch(Track track) async {
    final cleanTitle = _cleanSongTitle(track.title);
    final cleanArtist = _cleanSongArtist(track.artist);
    final song = await _extractor.searchSong('$cleanArtist $cleanTitle');
    final expectedSec = track.expectedDuration?.inSeconds;
    if (song.videoId != null &&
        isAcceptableSongMatch(
          resultTitle: song.title ?? '',
          resultDurationSec: song.duration?.inSeconds,
          targetTitle: cleanTitle,
          expectedSec: expectedSec != null && expectedSec > 0 ? expectedSec : null,
        )) {
      return _toResolved(song, song.videoId!, fallbackDuration: track.expectedDuration);
    }
    developer.log(
      'Song search result rejected for "$cleanArtist - $cleanTitle": "${song.title}" (${song.duration?.inSeconds}s vs $expectedSec s)',
      name: 'AudioStreamResolver',
    );
    return null;
  }

  /// Checks a download made from [downloadedVideoId] against song search,
  /// once, when that match was never checked. Returns the right recording's
  /// stream when the download is a different one; null when it's fine.
  /// Throws when it can't check now (offline, no song search), so the
  /// caller can try again another time.
  Future<ResolvedAudioStream?> checkDownloadedMatch(Track track, String downloadedVideoId) async {
    if (_isWeb || downloadedVideoId.isEmpty) return null;
    if (await isSettledMatch(track, downloadedVideoId)) return null;
    final key = _normKey(track);
    final found = await _searchSongMatch(track);
    if (found == null || found.sourceVideoId == downloadedVideoId) {
      // Nothing better to offer: the download stands.
      await _matchIndex.remember(
        key,
        MatchEntry(downloadedVideoId, source: found == null ? MatchSource.scoredSearch : MatchSource.songSearch),
      );
      return null;
    }
    developer.log('Download of "${track.title}" was $downloadedVideoId; the song is ${found.sourceVideoId}',
        name: 'AudioStreamResolver');
    await _rememberResolved(key, found, MatchSource.songSearch);
    return found;
  }

  Future<ResolvedAudioStream> _extractOnDevice(String videoId, {Duration? fallbackDuration}) async =>
      _toResolved(await _extractor.extract(videoId), videoId, fallbackDuration: fallbackDuration);

  ResolvedAudioStream _toResolved(ExtractedAudio audio, String videoId, {Duration? fallbackDuration}) {
    return ResolvedAudioStream(
      streamUri: audio.url,
      duration: audio.duration ?? fallbackDuration ?? Duration.zero,
      bitrateKbps: audio.bitrateKbps ?? 0,
      format: audio.container,
      sourceVideoId: videoId,
      headers: audio.headers,
    );
  }

  /// Remembers the video and, while it is valid, the stream link itself.
  Future<void> _rememberResolved(String key, ResolvedAudioStream resolved, MatchSource source) => _matchIndex.remember(
        key,
        MatchEntry(
          resolved.sourceVideoId,
          url: resolved.streamUri,
          expiresAt: MatchEntry.expiryOf(resolved.streamUri),
          durationMs: resolved.duration > Duration.zero ? resolved.duration.inMilliseconds : null,
          container: resolved.format,
          source: source,
        ),
      );

  /// Whether a saved audio copy made from [videoId] is still [track]'s
  /// settled match. A copy of an older, unchecked or replaced match isn't,
  /// so the track is matched again rather than replaying the wrong song.
  Future<bool> isSettledMatch(Track track, String videoId) async {
    if (videoId.isEmpty) return false;
    if (track.id == 'yt_$videoId') return true;
    final entry = await _matchIndex.lookup(_normKey(track));
    return entry != null && entry.isTrusted && entry.videoId == videoId;
  }

  /// The YouTube video [track] plays from on this device, if already known:
  /// its own `yt_` id or a trusted remembered match. Never searches.
  Future<String?> knownVideoId(Track track) async {
    if (track.id.startsWith('yt_')) return track.id.substring(3);
    if (_isWeb) return null;
    final entry = await _matchIndex.lookup(_normKey(track));
    return entry != null && entry.isTrusted ? entry.videoId : null;
  }

  /// Drops every cached entry for [track] so the next resolve starts fresh
  /// (stream URLs expire, and a URL that failed to load should not be reused).
  /// The remembered video stays; only its link is dropped.
  void forgetTrack(Track track) {
    if (!_isWeb) unawaited(_matchIndex.forgetLink(_normKey(track)));
    final cached = getCachedStream(track);
    _resolvedCache.remove(track.id);
    _resolvedCache.remove(_normKey(track));
    if (cached != null && cached.sourceVideoId.isNotEmpty) {
      _resolvedCache.remove(cached.sourceVideoId);
      _resolvedCache.remove('vid_${cached.sourceVideoId}');
    }
  }

  /// Queries the Symphony server's `/api/resolve` endpoint on Web to extract
  /// full-length YouTube audio stream proxies without 403 or CORS restrictions.
  Future<ResolvedAudioStream?> resolveViaWebServer(Track track, {String? videoId}) async {
    // Native builds never depend on a Symphony server.
    if (!_isWeb) return null;
    final cleanTitle = _cleanSongTitle(track.title);
    final cleanArtist = _cleanSongArtist(track.artist);
    final query = '$cleanArtist - $cleanTitle official audio';

    final candidateOrigins = ServerConfig.candidateOrigins();

    for (final origin in candidateOrigins) {
      try {
        final queryParams = <String, String>{};
        if (videoId != null && videoId.isNotEmpty) {
          queryParams['videoId'] = videoId;
        } else {
          queryParams['q'] = query;
          queryParams['artist'] = cleanArtist;
          queryParams['title'] = cleanTitle;
        }
        if (track.expectedDuration != null) {
          queryParams['durationMs'] = track.expectedDuration!.inMilliseconds.toString();
        }

        final uri = Uri.parse('$origin/api/resolve').replace(queryParameters: queryParams);
        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final streamUrl = data['streamUrl'] as String?;
          final durationMs = data['durationMs'] as int?;
          final format = (data['format'] as String?) ?? 'm4a';

          if (streamUrl != null && streamUrl.isNotEmpty) {
            final fullStreamUri = streamUrl.startsWith('http')
                ? Uri.parse(streamUrl)
                : Uri.parse(origin).resolve(streamUrl);

            developer.log(
              'Resolved full master stream via server API ($origin): "${track.title}" -> $fullStreamUri',
              name: 'AudioStreamResolver',
            );
            return ResolvedAudioStream(
              streamUri: fullStreamUri,
              duration: durationMs != null ? Duration(milliseconds: durationMs) : (track.expectedDuration ?? Duration.zero),
              bitrateKbps: (data['bitrate'] as num?)?.round() ?? 160,
              format: format,
              sourceVideoId: (data['videoId'] as String?) ?? track.id,
            );
          }
        }
      } catch (e) {
        developer.log('Server resolve attempt failed on $origin: $e', name: 'AudioStreamResolver');
      }
    }
    return null;
  }

  bool _isShortPreviewStream(Uri? uri) {
    if (uri == null) return false;
    final s = uri.toString().toLowerCase();
    return s.contains('audio-ssl.itunes.apple.com') ||
        s.contains('itunes.apple.com') ||
        s.contains('cdns-preview') ||
        s.contains('/preview/');
  }

  String _cleanSongTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(feat\.[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[feat\.[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(remix[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*remaster.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'- .*remaster.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'- .*version.*', caseSensitive: false), '')
        .trim();
  }

  String _cleanSongArtist(String artist) {
    return artist
        .split(RegExp(r'[,/&]|ft\.|feat\.', caseSensitive: false))
        .first
        .trim();
  }

  /// Second attempt after a stream failed to load: native re-extracts on the
  /// device with a fresh URL; web asks the server again.
  Future<ResolvedAudioStream?> resolveFallbackCdn(Track track) async {
    if (_isWeb) return resolveViaWebServer(track);
    forgetTrack(track);
    try {
      return await resolveBestAudioStream(track);
    } catch (e) {
      developer.log('Fresh on-device resolve failed for "${track.title}": $e', name: 'AudioStreamResolver');
      return null;
    }
  }

  /// Words that mark a different recording than the one asked for.
  static const _versionWords = [
    'live', 'acoustic', 'remix', 'instrumental', 'karaoke', 'cover', 'radio edit',
    'extended', 'sped up', 'slowed', 'demo', 'reverb', 'nightcore', '8d',
  ];

  static bool _hasUnwantedVersion(String candidateTitle, String targetTitle) {
    final c = candidateTitle.toLowerCase();
    final t = targetTitle.toLowerCase();
    return _versionWords.any((w) =>
        RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)').hasMatch(c) &&
        !RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)').hasMatch(t));
  }

  /// Whether a YouTube Music song result is the track we want: the right
  /// length (within max(6 s, 3 %)), the title's words present, and not a
  /// live/acoustic/remix/etc. version the track isn't.
  @visibleForTesting
  static bool isAcceptableSongMatch({
    required String resultTitle,
    required int? resultDurationSec,
    required String targetTitle,
    required int? expectedSec,
  }) {
    if (_hasUnwantedVersion(resultTitle, targetTitle)) return false;
    if (expectedSec != null) {
      if (resultDurationSec == null) return false;
      final tolerance = (expectedSec * 0.03).round().clamp(6, 20);
      if ((resultDurationSec - expectedSec).abs() > tolerance) return false;
    }
    String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final words = norm(targetTitle).split(RegExp(r'\s+')).where((w) => w.length >= 2).toSet();
    // Non-Latin titles (no ASCII words): rely on the length check.
    if (words.isEmpty) return expectedSec != null;
    final result = norm(resultTitle);
    final present = words.where(result.contains).length;
    final needed = expectedSec != null ? 0.6 : 0.85;
    return present / words.length >= needed;
  }

  static int scoreVideoCandidate({
    required String videoTitle,
    required String videoAuthor,
    required int durationSec,
    required String targetTitle,
    required String targetArtist,
    int? expectedDurationMs,
  }) {
    final vTitle = videoTitle.toLowerCase();
    final vAuthor = videoAuthor.toLowerCase();
    final tTitle = targetTitle.toLowerCase();
    final tArtist = targetArtist.toLowerCase();
    final expectedSec = expectedDurationMs != null ? (expectedDurationMs ~/ 1000) : 210;

    // 1. Hard disqualification: Videos > 11 minutes (660s) when expected track is normal song (< 9 mins)
    if (durationSec > 660 && expectedSec < 540) {
      return -9999;
    }
    // If expected duration is known, any video differing by > 45 seconds is rejected
    if (expectedDurationMs != null && expectedSec > 30 && (durationSec - expectedSec).abs() > 45 && expectedSec < 600) {
      return -9999;
    }
    // Videos < 45 seconds when expected track is > 60s
    if (durationSec < 45 && expectedSec > 60) {
      return -9999;
    }

    // 2. Disqualify obvious gameplay, walkthroughs, podcasts, non-music
    final redFlags = [
      'gameplay',
      'walkthrough',
      'playthrough',
      'lets play',
      'let\'s play',
      'podcast',
      'full album',
      'part 1',
      'part 2',
      'part 3',
      'part 4',
      'part 5',
      'part 6',
      'part 7',
      'part 8',
      'part 9',
      'part 10',
      'part 11',
      'part 12',
      'part 13',
      'part 14',
      'part 15',
      'part 16',
      'part 17',
      'part 18',
      'part 19',
      'part 20',
      'part 21',
      'part 22',
      'part 23',
      'episode ',
      'ep 1',
      'ep 2',
      'ep 3',
      'ep 4',
      'ep 5',
      'live stream',
      'livestream',
      'stream vod',
      'vod',
      'reaction',
      'reacts to',
      'reacting to',
      'elden ring',
      '1shotplays',
      'roblox',
      'minecraft',
      'fortnite',
      'gta',
      'review',
      'tier list',
      'unboxing',
      'speedrun',
      'boss fight',
      'cutscenes',
      'tutorial',
      '10 hours',
      '10 hour',
      '1 hour loop',
      'hour loop',
      '100 hours',
      'extended loop',
      'nightcore',
      'slowed + reverb',
      'slowed and reverb',
      '8d audio',
      'bass boosted',
      'pitch shifted',
      'parody',
      'cover by',
      'karaoke',
      'synthesia',
      'piano tutorial',
      'guitar tutorial',
      'guitar tab',
      'ai cover',
    ];
    for (final rf in redFlags) {
      if (vTitle.contains(rf) || vAuthor.contains(rf)) return -9999;
    }
    // Retuned uploads ("432 Hz", "528hz"): same title and length, wrong pitch.
    if (RegExp(r'\b\d{3}\s?hz\b').hasMatch(vTitle) && !RegExp(r'\b\d{3}\s?hz\b').hasMatch(tTitle)) return -9999;

    int score = 0;

    // 3. Match title keywords (MANDATORY)
    final cleanTTitle = tTitle.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
    final titleWords = cleanTTitle.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    int matchedTitleWords = 0;
    for (final w in titleWords) {
      if (vTitle.contains(w)) matchedTitleWords++;
    }
    if (titleWords.isNotEmpty) {
      if (matchedTitleWords == titleWords.length) {
        score += 70; // All title words matched
      } else if (matchedTitleWords > 0) {
        score += ((matchedTitleWords / titleWords.length) * 50).round();
      } else {
        // NONE of the title words matched: absolute disqualification
        return -9999;
      }
    }

    // Exact clean title substring match bonus
    if (cleanTTitle.isNotEmpty && vTitle.contains(cleanTTitle)) {
      score += 30;
    }

    // 4. Match artist keywords & Topic Channel
    final cleanTArtist = tArtist.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
    final artistWords = cleanTArtist.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    int matchedArtistWords = 0;
    for (final w in artistWords) {
      if (vTitle.contains(w) || vAuthor.contains(w)) {
        matchedArtistWords++;
      }
    }
    if (artistWords.isNotEmpty) {
      if (matchedArtistWords > 0) {
        score += 35;
      } else if (!vAuthor.contains('topic')) {
        score -= 30; // Artist name not found in title or channel
      }
    }

    // YouTube Music Topic Channel (official automated aggregator release: TuneCore, DistroKid, etc.)
    if (vAuthor.endsWith(' - topic') || vAuthor.contains('topic')) {
      score += 85;
    }

    // 5. Official audio indicators. Music videos get little credit: they often
    //    add intros/outros, so their length rarely matches the track.
    if (vTitle.contains('official audio')) {
      score += 45;
    } else if (vTitle.contains('official lyric video') || vTitle.contains('official visualizer')) {
      score += 30;
    } else if (vTitle.contains('official music video') || vTitle.contains('official video')) {
      score += 5;
    } else if (vTitle.contains('audio')) {
      score += 15;
    }

    // A different recording (live, acoustic, remix, radio edit...) than asked for.
    if (_hasUnwantedVersion(vTitle, tTitle)) {
      score -= 120;
    }

    // 6. Duration proximity: the strongest signal when the real length is known.
    final diffSec = (durationSec - expectedSec).abs();
    if (expectedDurationMs == null) {
      if (diffSec <= 60) score += 10;
    } else if (diffSec <= 2) {
      score += 90;
    } else if (diffSec <= 5) {
      score += 65;
    } else if (diffSec <= 10) {
      score += 25;
    } else if (diffSec <= 20) {
      score -= 25;
    } else {
      score -= 70;
    }

    return score;
  }

  void dispose() {
    clearCache();
    _extractor.dispose();
    _yt.close();
    _httpClient.close();
  }
}
