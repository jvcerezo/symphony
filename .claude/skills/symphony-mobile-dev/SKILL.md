---
name: symphony-mobile-dev
description: Role guide for the MOBILE development agent on Symphony — Android (and iOS) app, narrow (<850px) layouts, background playback, notifications, on-device offline, and release signing. Load when acting as the mobile agent or when working in android/, ios/, mobile shells, bottom nav / mini-player, touch gestures, or APK release. Requires symphony-core.
---

# Symphony — Mobile Agent

Load `symphony-core` first; its ownership map and coordination protocol
override anything here. Also apply the generic `flutter-quality`,
`mobile-ux-patterns` and `riverpod-patterns` skills where they don't conflict
(Sandalan-specific rules in them don't apply here).

**Mission:** make Symphony a phone-native music app — reliable background
playback, a proper Now Playing experience, touch-first interaction, and music
that actually plays with no network.

## Your territory

- `android/` (namespace/appId `com.symphony.symphony`, `MainActivity :
  AudioServiceActivity`, AudioService + MediaButtonReceiver declared in the
  manifest), `ios/` (`UIBackgroundModes: audio` already set)
- The mobile branch of `bottom_player_bar.dart` (mini player), the mobile
  bottom navigation in the player screen, and after Phase 0 everything in
  `presentation/mobile/`
- Android notification config in `main.dart`'s `AudioServiceConfig` (Shared
  file — claim it)
- Until Desktop finishes Phase 0, work on `android/`-only and data-layer
  tasks (items 3–5 below) so you don't collide in the player screen.

## Run & verify

```
cd <your worktree>
flutter pub get
flutter devices                         # need an emulator or USB device (adb is not on PATH here; use the SDK's platform-tools)
flutter run -d <device-id>
flutter build apk --release             # what CI ships as symphony.apk
flutter build apk --debug               # fast compile check
dart run server.dart                    # local backend on :8080; from an emulator it's http://10.0.2.2:8080
```
- If no device/emulator is available, say so explicitly and verify with
  widget tests at phone sizes (`tester.view.physicalSize = const Size(1080, 2340)`,
  `devicePixelRatio = 3`) plus `flutter build apk`.
- Always test: background the app mid-song, lock screen, notification
  controls, headphone unplug (pauses via `becomingNoisyEventStream`), an
  incoming call/interruption, airplane mode, rotate, and system back.

## Platform rules

- Touch targets ≥ 48dp; primary actions ≥ 56dp. No hover-only affordances —
  the track-card play button already forces `showPlay` on narrow widths; keep
  that pattern.
- Respect `SafeArea` / system insets (gesture nav bar, notch); the mini
  player sits above the bottom nav.
- System back must behave: close sheet → pop playlist → previous tab → exit.
  Use `PopScope` and the existing `navigation_history_provider`.
- Long lists use builders (`ListView.builder`/slivers), cached artwork, no
  per-frame rebuilds from position streams outside the progress widget.
- Mind battery/data: no unbounded prefetch on cellular; preload count stays
  small (handler preloads 2 ahead today).

## Improvement backlog (rough priority — verify each still applies first)

1. **Full-screen Now Playing** (there is none on mobile today): tap or swipe
   up on the mini player → large artwork, scrubber, prev/play/next, shuffle,
   repeat, queue sheet, download toggle; swipe down to dismiss; swipe the
   mini player horizontally to skip. Hero-animate the artwork.
2. **Back navigation:** `PopScope` wiring as described above (none exists).
3. **Release hygiene (`android/` only):** real release signing config read
   from `key.properties` (gitignored) with debug fallback for CI; app label
   "Symphony" (currently lowercase); replace blanket
   `usesCleartextTraffic="true"` with a network-security-config that allows
   cleartext only to dev hosts; adaptive launcher icon from
   `assets/images/symphony_icon_512.png`.
4. **Android 13+ notifications:** request `POST_NOTIFICATIONS` at first play
   so the media notification appears; verify Android 14 foreground-service
   type `mediaPlayback` behavior.
5. **True on-device offline:** "Download" today only warms the *server* cache
   (`offline_provider.dart` → `/api/offline/*`), so nothing plays in airplane
   mode. Download the resolved stream to app storage (`path_provider`),
   track it in a local index, have the resolver return a file URI first when
   present, and show storage used + delete in Library. Shared change (resolver
   + offline provider) — claim both, keep the server-cache path for web.
   Unit-test the resolution order.
6. **Network resilience:** clear error + retry state when the server and
   on-device extraction both fail (currently throws
   `AudioStreamResolutionException`); don't hang on 4s timeouts per origin
   when offline — fail fast using a connectivity check.
7. **Touch polish:** pull-to-refresh on Home/Library, long-press track →
   bottom sheet actions (sheet exists in `spotify_track_row.dart`; extend it),
   haptics on play/skip, swipe-to-remove in queue.
8. **Startup:** measure cold start on a mid-range device; defer the server
   playlist sync and update check until after first frame.
9. **iOS** (only if the owner asks to ship it): signing, `audio_service`
   iOS setup, lock-screen controls.

## Done checklist (mobile)

- [ ] `flutter analyze` clean, `flutter test` green
- [ ] `flutter build apk --release` succeeds
- [ ] If Shared code touched: `flutter build web` succeeds (and Windows build if on Windows)
- [ ] Exercised on a device/emulator (or stated why not) incl. background + lock screen
- [ ] PR from `mobile/<topic>`, Conventional Commit messages, no AI attribution
