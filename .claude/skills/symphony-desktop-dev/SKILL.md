---
name: symphony-desktop-dev
description: Role guide for the DESKTOP development agent on Symphony — Windows desktop app, wide (>=850px) layouts, web landing page, and the Windows auto-updater. Load when acting as the desktop agent or when working in windows/, web/, lib/features/landing/, sidebar_nav, desktop shells, keyboard/mouse interaction, or Windows packaging. Requires symphony-core.
---

# Symphony — Desktop Agent

Load `symphony-core` first; its ownership map and coordination protocol
override anything here.

**Mission:** make Symphony feel like a first-class Windows music app —
keyboard-driven, responsive to mouse/hover, OS-integrated, and reliable to
install and update. You also own the wide web layout and the landing page.

## Your territory

- `windows/` (runner: `main.cpp` creates a 1280×720 "Symphony" window),
  `linux/`, `macos/`
- `lib/core/services/windows_auto_updater_io.dart` (downloads zip, swaps
  install, relaunches) + `app_update_dialog.dart` Windows branch
- `sidebar_nav.dart`, `nav_history_controls.dart`, the desktop branch of
  `bottom_player_bar.dart`, and after Phase 0 everything in
  `presentation/desktop/`
- `web/`, `lib/features/landing/` (landing page, `wave_background.dart`)
- Phase 0 in `symphony-core` is **yours** — do it first.

## Run & verify

```
cd <your worktree>
flutter pub get
flutter run -d windows                     # debug
flutter build windows --release            # what CI ships (zip of build\windows\x64\runner\Release)
flutter run -d chrome --web-port 5000      # web; append #player for the demo player
dart run server.dart                       # local backend on :8080 (resolve/stream/playlists)
```
- Playback on Windows uses `just_audio_windows`; `AudioSession` is skipped on
  Windows/Linux (see `_initAudioSession`). Native AAC (m4a) is preferred —
  commit `0225267` fixed infinite loading by enforcing it; don't regress.
- Test at 850px (breakpoint edge), 1280×720, and 1920×1080. Resize live —
  layouts must not overflow (watch the debug console for RenderFlex errors).
- The owner may be using the app while you work. **Ask before launching
  extra Windows app windows** if they say they're demoing; prefer
  `flutter test` / widget tests for verification in that case.

## Platform rules

- Hover affordances are fine on desktop, but every hover-only action must also
  be reachable by keyboard and right-click.
- Use `Shortcuts`/`Actions`/`Intent` (or `CallbackShortcuts` at the shell)
  for keybindings — never raw `RawKeyboardListener`. Don't steal keys while a
  `TextField` has focus.
- Use `MouseRegion` + `SystemMouseCursors.click` on clickable non-buttons.
- Windows-only packages go behind a conditional import or a
  `defaultTargetPlatform == TargetPlatform.windows` guard and must not break
  `flutter build apk` / `flutter build web`.
- Text density: desktop can use tighter spacing than mobile, but keep the
  type scale from `SymphonyTheme`.

## Improvement backlog (rough priority — verify each still applies first)

1. **Phase 0** (breakpoints, split the 2.2k-line screen, central server config).
2. **Keyboard shortcuts:** Space play/pause, Ctrl+→/← next/prev, Shift+→/← seek
   ±10s, Ctrl+↑/↓ volume, Ctrl+F / `/` focus search, Alt+←/→ nav history
   (wire to `navigation_history_provider`), Esc closes dialogs. Add a "?"
   shortcuts overlay. Widget-test the bindings.
3. **OS media integration:** hardware media keys + Windows SMTC (the
   lock-screen/volume-flyout media card). `audio_service` doesn't cover
   Windows — evaluate a maintained SMTC plugin, isolate it behind a
   conditional import, feed it from the handler's `mediaItem`/`playbackState`.
4. **Window behavior:** minimum size (≥ 900×600 so the desktop layout never
   collapses awkwardly), remember size/position across launches, window title
   = "Title — Artist · Symphony" while playing.
5. **Right-click context menus** on track rows and playlist cards (play next,
   add to queue, download, copy link, remove) and **drag-to-reorder** in the
   queue panel.
6. **Queue / Now-Playing side panel** on wide screens (≥1280): current queue,
   upcoming, lyrics placeholder; collapsible.
7. **Updater hardening:** verify download size/hash before swapping, keep the
   previous build for rollback, clear failure messaging in the dialog, never
   leave a half-extracted install. Add tests around `AppReleaseInfo` parsing
   edge cases (`app_update_test.dart` exists).
8. **Packaging:** ship an installer (MSIX or Inno Setup) with Start-menu
   shortcut and proper app icon/version metadata in `Runner.rc`, alongside
   the zip. CI change → Shared, claim `.github/workflows/deploy.yml`.
9. **Web/landing:** Lighthouse pass (performance, a11y), meta/OG tags,
   respect `prefers-reduced-motion` in `wave_background.dart`.

## Done checklist (desktop)

- [ ] `flutter analyze` clean, `flutter test` green
- [ ] `flutter build windows --release` succeeds
- [ ] If Shared code touched: `flutter build apk --debug` and `flutter build web` succeed
- [ ] Exercised on Windows at 850px and full-width; keyboard path works
- [ ] PR from `desktop/<topic>`, Conventional Commit messages, no AI attribution
