import 'match_index_stub.dart' if (dart.library.io) 'match_index_io.dart' as impl;

/// How a match was found.
enum MatchSource {
  /// YouTube Music's song search: the album recording.
  songSearch('s'),

  /// The track came with its YouTube video (e.g. a YouTube playlist).
  videoId('i'),

  /// Scored general YouTube search, after song search found nothing.
  scoredSearch('f');

  const MatchSource(this.code);
  final String code;

  static MatchSource? fromCode(Object? code) =>
      MatchSource.values.where((s) => s.code == code).firstOrNull;
}

/// What a track resolved to: the YouTube video, plus (while still valid) the
/// stream link itself, so a replay within a few hours needs no yt-dlp run.
class MatchEntry {
  final String videoId;
  final Uri? url;
  final DateTime? expiresAt;
  final int? durationMs;
  final String? container;

  /// Null for matches saved before sources were recorded. Some of those came
  /// from a fallback search while yt-dlp couldn't start on Android, so they
  /// are checked against song search once before being trusted.
  final MatchSource? source;

  const MatchEntry(this.videoId, {this.url, this.expiresAt, this.durationMs, this.container, this.source});

  /// Settled: found by a search that knew about song search, or given.
  bool get isTrusted => source != null;

  /// Safety margin so a link never expires mid-song.
  static const expiryMargin = Duration(minutes: 20);

  bool get hasFreshLink =>
      url != null && expiresAt != null && expiresAt!.isAfter(DateTime.now().add(expiryMargin));

  MatchEntry withoutLink() => MatchEntry(videoId, source: source);

  Map<String, dynamic> toJson() => {
        'v': videoId,
        if (url != null) 'u': url.toString(),
        if (expiresAt != null) 'e': expiresAt!.millisecondsSinceEpoch ~/ 1000,
        if (durationMs != null) 'd': durationMs,
        if (container != null) 'c': container,
        if (source != null) 'm': source!.code,
      };

  /// Accepts the compact map form, or a bare video id (older files).
  static MatchEntry? fromJson(Object? json) {
    if (json is String && json.isNotEmpty) return MatchEntry(json);
    if (json is! Map) return null;
    final v = json['v'];
    if (v is! String || v.isEmpty) return null;
    final e = json['e'];
    return MatchEntry(
      v,
      url: json['u'] is String ? Uri.tryParse(json['u'] as String) : null,
      expiresAt: e is int ? DateTime.fromMillisecondsSinceEpoch(e * 1000) : null,
      durationMs: json['d'] is int ? json['d'] as int : null,
      container: json['c'] as String?,
      source: MatchSource.fromCode(json['m']),
    );
  }

  /// Expiry encoded in a YouTube CDN link (`expire=<unix seconds>`), if any.
  static DateTime? expiryOf(Uri url) {
    final e = int.tryParse(url.queryParameters['expire'] ?? '');
    return e == null ? null : DateTime.fromMillisecondsSinceEpoch(e * 1000);
  }
}

/// Remembers which YouTube video (and, briefly, which stream link) a track
/// resolved to, so replays skip the search and often yt-dlp entirely.
abstract interface class MatchIndex {
  /// Shared instance: file-backed on native, in-memory on web.
  static MatchIndex platform() => _platform ??= impl.createPlatformMatchIndex();
  static MatchIndex? _platform;

  Future<MatchEntry?> lookup(String key);
  Future<void> remember(String key, MatchEntry entry);

  /// Keeps the video id but drops the link (it failed or expired).
  Future<void> forgetLink(String key);
  Future<void> forget(String key);
}

/// Process-lifetime index (web, tests).
class MemoryMatchIndex implements MatchIndex {
  final _map = <String, MatchEntry>{};

  @override
  Future<MatchEntry?> lookup(String key) async => _map[key];

  @override
  Future<void> remember(String key, MatchEntry entry) async => _map[key] = entry;

  @override
  Future<void> forgetLink(String key) async {
    final e = _map[key];
    if (e != null) _map[key] = e.withoutLink();
  }

  @override
  Future<void> forget(String key) async => _map.remove(key);
}
