# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

## 2026-10-10 — [mobile] On-device offline downloads, data layer (branch `mobile/release-hygiene`)

New (all under `lib/features/audio_player/data/services/offline/`):
- `LocalTrackStore` interface + `LocalTrackStore.platform()` shared instance.
  Conditional import: `local_track_store_io.dart` (files + `index.json` in
  `<getApplicationSupportDirectory>/offline_tracks/`) on native,
  `UnsupportedLocalTrackStore` on web. API: `isSupported`, `lookup(track)`,
  `save(track, bytes, …)`, `remove(track)` → bytes freed, `entries()`,
  `totalBytes()`. `LocalTrackEntry.matchKeys` = the keys
  `OfflineState.isTrackDownloaded` checks.
- `OfflineDownloadService(resolve:, store:, httpClient:)`:
  `download(track, onProgress:)`, `remove`, `entries`, `totalBytes`.

Changed (additive):
- `AudioStreamResolverService`: new optional ctor params `localTracks:` and
  `@visibleForTesting isWeb:`; new `resolveLocal(track)` and `localTracks`
  getter. `resolveBestAudioStream` now returns a `file://` stream first when
  the track is downloaded (non-web only); local hits are not memory-cached.
  Web behavior is unchanged.
- `OfflineManagerNotifier({deviceDownloads:, client:})`; the provider passes
  an `OfflineDownloadService` on every non-web platform, **including Windows**.
  There `downloadTrack` / `downloadPlaylist` / `removeDownloadedPlaylist` now
  work against device storage, and `cachedKeys` comes from the local index
  instead of the server's `/api/offline/status`. Web still uses the server
  cache. New: `removeDownloadedTrack(track)` and `deviceStorageBytes()`. No UI
  uses these yet.

Desktop: existing call sites compile unchanged. Expect "Downloaded" badges on
Windows to show only tracks saved on this machine (tracks warmed in the server
cache no longer count). Storage-used and delete UI in Library is still to do.

## 2026-10-10 — [mobile] POST_NOTIFICATIONS at first playback (branch `mobile/release-hygiene`)

- New `lib/core/services/notification_permission_service.dart`
  (`NotificationPermissionService.ensureRequested()`): method channel
  `com.symphony.symphony/notifications` implemented in Android `MainActivity`.
  Returns `true` without any platform call on web/Windows/other platforms.
- `SymphonyAudioHandler` gained an optional `notificationPermission:` ctor
  parameter (defaults to the real service) and calls it, non-blocking, at the
  start of every track load (memoized, so it only prompts once per process).
  Desktop: no action needed; existing constructor calls are unchanged.
- `main.dart`: `androidNotificationIcon` is now `drawable/ic_stat_symphony`
  (Android-only setting).

