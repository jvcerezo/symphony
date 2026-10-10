---
name: symphony-core
description: Shared architecture, file-ownership map, coordination protocol, and quality gates for the Symphony Flutter music player (Windows desktop + Android/iOS mobile + web, one lib/). Auto-load for ANY work in the symphony repo, and always before loading symphony-desktop-dev or symphony-mobile-dev. Two agents (desktop + mobile) develop in parallel; this skill keeps them from colliding.
---

# Symphony — Core (both agents read this first)

Symphony is a minimalist, Spotify-style music player. Users import playlists
(Spotify / YouTube / Apple Music links) or search iTunes/Deezer metadata;
audio is resolved to full-length YouTube streams and played with `just_audio`.
One Flutter codebase ships to **Windows desktop**, **Android** (iOS configured,
not shipped), and **web** (landing page + web demo served by `server.dart`).

Your job, in either role, is to **improve and enhance the app**: fix real
bugs, make it feel native on your platform, and leave the codebase easier
to work in than you found it.

## Architecture map

```
lib/
  main.dart                         AudioService.init → ProviderScope → MaterialApp
  core/
    constants/curated_playlists.dart  starter playlists shown on Home
    theme/symphony_theme.dart         ALL colors/accents (SymphonyTheme.*, SymphonyAccent)
    services/app_update_service.dart  GitHub Releases check (latest tag)
    services/windows_auto_updater*.dart  conditional import: _io (Windows) / _stub
    utils/platform_url_launcher*.dart    conditional import: _web / _stub
    widgets/                          brand logo, update dialog
  features/
    audio_player/
      domain/entities/                Track, ResolvedAudioStream (pure Dart)
      data/services/
        symphony_audio_handler.dart   BaseAudioHandler: queue, skip, completion watchdog
        audio_stream_resolver_service.dart  resolve order: server /api/resolve → on-device youtube_explode → track.streamUri
      presentation/
        controllers/                  Riverpod providers (StateProvider/StateNotifier/StreamProvider)
        views/symphony_player_screen.dart   2.2k-line shell: Home / Search / Library / Playlist
        widgets/                      bottom_player_bar, sidebar_nav, track rows, dialogs
    metadata_search/                  iTunes/Deezer search + artwork resolver
    playlist_import/                  Spotify embed scraper, universal importer
    settings/                         personalization (accent, instance id)
    landing/                          web landing page + wave background
server.dart                           headless Dart backend: /api/resolve, /api/stream, /api/playlists, /api/offline/*
.github/workflows/deploy.yml          analyze → test → web + APK → Windows zip → GitHub Release "latest" → GHCR → Render/Koyeb
```

**State:** `flutter_riverpod` 2.x, legacy `StateProvider`/`StateNotifier`.
Do not migrate to codegen/Notifier in passing; follow the file's existing style.
`audioHandlerProvider` is overridden in `main.dart` — never construct a second
`SymphonyAudioHandler`.

**Layout switch today:** `symphony_player_screen.dart` uses
`MediaQuery.width >= 850` → desktop (sidebar) vs mobile (bottom nav).
`bottom_player_bar.dart` uses `< 750`, track cards use `< 700`. These
inconsistent breakpoints are a known defect (see "Phase 0").

**Backend coupling:** the client tries several server origins in order
(prod `https://symphony.jettimothycerezo.dev`, a hardcoded LAN IP, localhost).
The same origin list is duplicated in `audio_player_providers.dart`,
`offline_provider.dart` and `audio_stream_resolver_service.dart`.
"Offline" downloads are currently a **server-side cache**, not files on the
device.

## Ownership map — who may edit what

| Area | Owner | Rule |
|---|---|---|
| `windows/`, `linux/`, `macos/`, `lib/core/services/windows_auto_updater*` | **Desktop** | Mobile never touches |
| `web/`, `lib/features/landing/` | **Desktop** | Mobile never touches |
| `sidebar_nav.dart`, `nav_history_controls.dart`, `lib/features/*/presentation/desktop/**` | **Desktop** | |
| `android/`, `ios/` | **Mobile** | Desktop never touches |
| `lib/features/*/presentation/mobile/**` | **Mobile** | |
| `symphony_player_screen.dart`, `bottom_player_bar.dart` | **Split** | Until Phase 0 lands, edit only the branch for your layout (`if (isDesktop)` / `isMobile`) and keep the diff small |
| `lib/main.dart`, `domain/`, `data/services/`, `controllers/`, `core/theme/`, `core/constants/` | **Shared** | Coordination protocol below |
| `pubspec.yaml`/`pubspec.lock`, `server.dart`, `pubspec.server.yaml`, `Dockerfile`, `.github/workflows/` | **Shared** | Coordination protocol below |
| `test/` | Whoever owns the code under test | |

## Coordination protocol (parallel agents)

1. **Separate worktrees, separate branches.** Never run both agents in the same
   checkout. From the repo root:
   ```
   git worktree add ../symphony-desktop -b desktop/<topic> main
   git worktree add ../symphony-mobile  -b mobile/<topic>  main
   ```
   Branch prefixes: `desktop/…`, `mobile/…`, `shared/…`.
2. **Before touching a Shared file**, append a line to
   `.claude/coordination/CLAIMS.md` on `main` (commit it alone, push):
   `- [desktop|mobile] <file or symbol> — <why> — <date>`. If the other agent
   already claims it, pick other work or message them; don't edit.
   Remove your line when your branch merges.
3. **Shared changes must be additive and platform-neutral.** Add a parameter
   with a default, a new method, a new provider. Do not rename or change the
   behavior of something the other platform uses without a claim and a note.
4. **Dependencies:** adding a package to `pubspec.yaml` is a Shared change.
   Prefer packages that compile on Android, Windows AND web, or isolate them
   behind a conditional import (`foo.dart` → `foo_io.dart` / `foo_stub.dart`,
   exactly like `windows_auto_updater.dart`). A plugin that breaks
   `flutter build web` or `flutter build apk` breaks CI for both agents.
5. **Rebase often:** `git fetch && git rebase origin/main` before each new
   task and before opening a PR.
6. **Hand-off notes:** when you change a Shared API, add an entry to
   `.claude/coordination/CHANGELOG.md` (what changed, how the other side
   should adapt).

## Phase 0 — unblock parallel work (do once, by Desktop, before UI features)

Mobile works on `android/`-only and data-layer tasks meanwhile.

1. Add `lib/core/layout/breakpoints.dart`:
   ```dart
   abstract final class Breakpoints {
     static const double desktop = 850;
     static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= desktop;
   }
   ```
   Replace the 850/750/700 literals with it.
2. Split `symphony_player_screen.dart` into a thin router plus
   `presentation/desktop/desktop_shell.dart` and
   `presentation/mobile/mobile_shell.dart`; move shared views (home, library,
   playlist content) into `presentation/views/sections/` as widgets that take
   `isDesktop` or read `Breakpoints`. Pure move — no behavior change; prove it
   with `flutter test` + a manual run.
3. Extract the duplicated server-origin lists into
   `lib/core/config/server_config.dart` (one ordered list, LAN dev host only in
   `kDebugMode`, overridable via `--dart-define=SYMPHONY_SERVER=…`).

## Quality gates (every change, both agents)

```
flutter analyze            # must be no new warnings/errors
flutter test               # must be green
```
Plus the platform build for your side (see your role skill). If you touched
Shared code, also run the other side's compile check:
`flutter build apk --debug` (desktop agent) / `flutter build windows --debug`
(mobile agent, only if on Windows) and `flutter build web`.

Code rules:
- Colors only from `SymphonyTheme` / the active `SymphonyAccent`; no new hex literals in widgets.
- Single quotes (lint `prefer_single_quotes`). Log with `developer.log(..., name: '<Area>')`, not `print`.
- New logic in services/notifiers gets a unit test in `test/` (see `candidate_scoring_test.dart`, `navigation_history_test.dart` for style). Inject `http.Client`/`AudioPlayer` via constructor for testability — the existing services already allow this.
- Don't grow `symphony_player_screen.dart`. New UI goes in its own widget file.
- Platform checks: `kIsWeb` first, then `defaultTargetPlatform`. Never import `dart:io` or `dart:html` outside a conditional-import file.
- Every async UI path needs loading, error and empty states.

## Commits & PRs

- Conventional Commits with a scope: `feat(desktop): …`, `fix(mobile): …`,
  `refactor(core): …`, `chore(ci): …` — matches existing history.
- **No AI attribution**: no "Claude", no `Co-Authored-By` trailer, no
  "Generated with" footer in commits or PRs.
- One concern per commit. Don't commit `build/`, `.symphony_cache/`, or
  unrelated working-tree changes you didn't make — check `git status` first;
  the owner may have uncommitted work in progress.
- Pushing to `main` triggers a public GitHub Release + cloud deploy. Open a PR
  from your branch instead; only merge to `main` when the owner says so.

## Definition of done

Analyze + tests + your platform build pass; you ran the app and exercised the
change on your platform (or say clearly you couldn't); Shared changes are
claimed and logged; the PR description lists what you verified and any
follow-up for the other agent.
