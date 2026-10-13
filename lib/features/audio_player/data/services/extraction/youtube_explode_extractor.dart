import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Pure-Dart fallback, and the only extractor on iOS (which cannot run
/// yt-dlp). YouTube often serves these links only partly: the first bytes
/// load, then it answers 403, so playback stalls a few seconds in. Each link
/// is therefore checked with a request from the middle of the file, and other
/// YouTube clients are tried until one serves the whole song.
class YoutubeExplodeExtractor implements AudioExtractor {
  /// Client sets tried in order; null lets the library choose.
  static const clientSets = <List<YoutubeApiClient>?>[
    null,
    [YoutubeApiClient.androidVr],
    [YoutubeApiClient.android],
    [YoutubeApiClient.tv],
  ];

  final YoutubeExplode _yt;
  final http.Client _http;

  YoutubeExplodeExtractor(this._yt, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  @override
  String get name => 'youtube_explode';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ExtractedAudio> extract(String videoId) async {
    Object? lastError;
    final best = await firstWorking<AudioOnlyStreamInfo>(
      [
        for (final clients in clientSets)
          () async {
            try {
              return _pickAudio(await _yt.videos.streamsClient.getManifest(videoId, ytClients: clients));
            } catch (e) {
              lastError = e;
              return null;
            }
          },
      ],
      (stream) => _servesMiddle(stream),
    );
    if (best == null) {
      throw AudioStreamResolutionException('youtube_explode found no full stream for $videoId', lastError);
    }
    return ExtractedAudio(
      url: best.url,
      container: best.container.name == 'mp4' ? 'm4a' : best.container.name,
      bitrateKbps: best.bitrate.kiloBitsPerSecond.round(),
    );
  }

  /// AAC in MP4 when there is one: Apple's player cannot play WebM/Opus.
  static AudioOnlyStreamInfo? _pickAudio(StreamManifest manifest) {
    final audio = manifest.audioOnly;
    if (audio.isEmpty) return null;
    final aac = audio.where((s) =>
        s.container.name == 'mp4' || s.codec.mimeType.contains('mp4') || s.codec.mimeType.contains('aac'));
    return aac.isNotEmpty ? aac.withHighestBitrate() : audio.withHighestBitrate();
  }

  /// One byte from the middle: a link YouTube will cut off fails here.
  Future<bool> _servesMiddle(AudioOnlyStreamInfo stream) async {
    final middle = stream.size.totalBytes ~/ 2;
    try {
      final response = await _http
          .get(stream.url, headers: {'Range': 'bytes=$middle-$middle'})
          .timeout(const Duration(seconds: 8));
      final ok = response.statusCode == 206 || response.statusCode == 200;
      if (!ok) developer.log('Link refused mid-file (${response.statusCode})', name: 'YoutubeExplode');
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ExtractedAudio> searchSong(String query) =>
      Future.error(UnsupportedError('youtube_explode cannot search YouTube Music'));

  // The YoutubeExplode client is owned by the resolver.
  @override
  void dispose() {}
}

/// Runs [attempts] in order and returns the first result that [works], or
/// null when none does. An attempt returning null is skipped.
@visibleForTesting
Future<T?> firstWorking<T>(List<Future<T?> Function()> attempts, Future<bool> Function(T value) works) async {
  for (final attempt in attempts) {
    final value = await attempt();
    if (value != null && await works(value)) return value;
  }
  return null;
}
