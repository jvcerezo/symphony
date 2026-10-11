import 'local_track_store.dart';

LocalTrackStore createPlatformLocalTrackStore() => const UnsupportedLocalTrackStore();

LocalTrackStore createPlatformPlaybackCacheStore() => const UnsupportedLocalTrackStore();
