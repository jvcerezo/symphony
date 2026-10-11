import 'match_index_stub.dart' if (dart.library.io) 'match_index_io.dart' as impl;

/// Remembers which YouTube video a track resolved to, so replaying it later
/// (even after its cached audio is evicted) skips the search entirely.
abstract interface class MatchIndex {
  /// Shared instance: file-backed on native, in-memory on web.
  static MatchIndex platform() => _platform ??= impl.createPlatformMatchIndex();
  static MatchIndex? _platform;

  Future<String?> lookup(String key);
  Future<void> remember(String key, String videoId);
  Future<void> forget(String key);
}

/// Process-lifetime index (web, tests).
class MemoryMatchIndex implements MatchIndex {
  final _map = <String, String>{};

  @override
  Future<String?> lookup(String key) async => _map[key];

  @override
  Future<void> remember(String key, String videoId) async => _map[key] = videoId;

  @override
  Future<void> forget(String key) async => _map.remove(key);
}
