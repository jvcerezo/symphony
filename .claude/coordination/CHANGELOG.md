# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

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

