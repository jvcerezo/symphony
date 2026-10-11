# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

## 2026-10-11 — [desktop] Windows yt-dlp extractor (branch `desktop/ytdlp-windows`)

- `WindowsYtDlpExtractor` (`extraction/windows_ytdlp_extractor_io.dart`) is
  implemented. Binary lookup: `<app support>\yt-dlp\yt-dlp.exe` (writable,
  self-updated) → `<dir of symphony.exe>\yt-dlp.exe` (bundled by CI).
  Runs `-f "ba[ext=m4a]/ba[acodec^=mp4a]/ba" -j --no-playlist --no-warnings`
  with a 25 s timeout (process tree killed on timeout), no console window.
  Concurrent `extract()` calls for one id share one process. Constructor
  takes an injectable `YtDlpProcessRunner`, `supportDir`, `exeDir`,
  `isWindows`, `timeout` for tests.
- New public `update()` on `WindowsYtDlpExtractor` (and the web stub, which
  returns null): copies the bundled exe to app support if needed, runs
  `yt-dlp -U`, returns the new version or null. Never throws. While it runs,
  extraction uses the bundled exe. Not part of the `AudioExtractor` contract.
- New `extraction/ytdlp_update_scheduler.dart` (`YtDlpUpdateScheduler`):
  platform-neutral "at most once per calendar day" gate in
  shared_preferences key `ytdlp_last_update_check`. `main.dart` schedules it
  30 s after start on Windows only. Mobile can reuse it with
  `AndroidYtDlpExtractor`'s `update` once the channel exists.
- CI (`deploy.yml`, Windows job): downloads the latest official
  `yt-dlp.exe` into `build\windows\x64\runner\Release\` before zipping and
  fails the job if it doesn't run. `yt-dlp.exe` is git-ignored.
- JS runtime: yt-dlp 2026.08.19 only enables `deno` by default. Without any
  runtime, YouTube audio (itag 140 m4a) still extracts and serves 206 for
  start/middle/end Range requests (verified 2026-10-11), with a deprecation
  warning. Nothing is bundled. If YouTube starts requiring one, drop
  `deno.exe` (~43 MB zipped) or quickjs-ng `qjs.exe` (~2.1 MB, lightest) next
  to the yt-dlp.exe in use; the extractor passes `--js-runtimes` automatically.

## 2026-10-11 — [core] Native apps no longer use any Symphony server

- New `lib/features/audio_player/data/services/extraction/`: `AudioExtractor`,
  `ExtractedAudio`, `ChainedAudioExtractor`, `createPlatformAudioExtractor(yt)`.
  - `WindowsYtDlpExtractor` (`_io`/`_stub` conditional import) — **stub,
    Desktop implements** (bundled `yt-dlp.exe`).
  - `AndroidYtDlpExtractor` — Dart side done; **Mobile implements the Kotlin
    side** of channel `com.symphony.symphony/ytdlp` (`isAvailable`, `extract`,
    `update`; contract in the file's doc comment).
  - `YoutubeExplodeExtractor` — last resort.
- `AudioStreamResolverService` is now a factory taking optional `extractor:`.
  Native never calls `/api/*`; web still uses the server. New `forgetTrack()`;
  `resolveFallbackCdn()` re-extracts fresh on native.
- `ResolvedAudioStream.headers` (optional) is honored by the audio handler and
  `OfflineDownloadService`.
- `ServerConfig.candidateOrigins()` returns nothing on native unless
  `SYMPHONY_SERVER` is defined; `preferLocal`, `isDebug`, `lanDevOrigin`,
  `localOrigins` were removed. Playlist sync, Spotify-import-via-server and
  server offline status are therefore off on native.

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

## 2026-10-10 — [desktop] Desktop keyboard shortcuts

- New `presentation/desktop/desktop_shortcuts.dart` (`DesktopShortcuts`,
  installed only by `DesktopShell`; mobile unaffected). Space, Ctrl+←/→,
  Shift+←/→ (±10 s), Ctrl+↑/↓, Ctrl+F or `/`, Alt+←/→, Esc, `?` overlay.
  Shortcuts are disabled while a text field is focused.
- New `presentation/desktop/desktop_volume_provider.dart` (`volumeProvider`):
  the desktop player bar's volume/mute state moved here from the bar's
  private fields so shortcuts and the slider agree. Only the desktop branch
  of `bottom_player_bar.dart` changed.
- New `metadata_search/presentation/controllers/search_focus_provider.dart`
  (`searchFieldFocusNodeProvider`), attached to the Search tab's TextField in
  `search_view.dart` (one added line). Mobile can reuse it to focus search.

## 2026-10-10 — [desktop] Phase 0c: central server config

- New `lib/core/config/server_config.dart`:
  - `ServerConfig.candidateOrigins({bool preferLocal = false})` — ordered,
    de-duplicated origins. Native: prod → LAN `192.168.1.57:8080`
    (**debug builds only**) → localhost → 127.0.0.1. `preferLocal: true`
    (used by `/api/resolve`): 127.0.0.1 → localhost → prod → LAN. Web: page
    origin only.
  - `ServerConfig.primaryOrigin()` — single origin for non-retried calls
    (offline download/remove; was hardcoded prod / page origin).
  - `ServerConfig.isSymphonyHost(host)` — used by the audio handler to skip
    YouTube headers for our own backends.
  - `--dart-define=SYMPHONY_SERVER=http://host:port` is tried first
    everywhere (fallbacks remain) and becomes `primaryOrigin()`.
- Replaced the duplicated lists in `audio_player_providers.dart`,
  `offline_provider.dart`, `audio_stream_resolver_service.dart`,
  `spotify_embed_scraper_service.dart`; host check in
  `symphony_audio_handler.dart`.
- **Behavior change:** release builds no longer try the hardcoded LAN IP.
  Mobile: to test a phone against a dev machine, run
  `flutter run --dart-define=SYMPHONY_SERVER=http://<your-lan-ip>:8080`.
  Never add hosts in services — extend `ServerConfig`.

## 2026-10-10 — [desktop] Phase 0b: player screen split (WHERE MOBILE UI NOW LIVES)

`symphony_player_screen.dart` (was 2,242 lines) is now a thin router. Pure
move — no behavior change. All paths below are under
`lib/features/audio_player/presentation/`.

| Was (in symphony_player_screen.dart) | Now |
|---|---|
| `build()` Scaffold, `!isDesktop` branch: BottomNavigationBar, edge-to-edge panel | `mobile/mobile_shell.dart` → `MobileShell` (**mobile-owned**) |
| `build()` Scaffold, `isDesktop` branch: SidebarNav, rounded panel | `desktop/desktop_shell.dart` → `DesktopShell` (desktop-owned) |
| `_buildHeroHeader` `if (!isDesktop)` branch | `mobile/mobile_playlist_hero.dart` → `MobilePlaylistHero` (**mobile-owned**) |
| `_buildHeroHeader` desktop branch (incl. "more options" menu) | `desktop/desktop_playlist_hero.dart` → `DesktopPlaylistHero` |
| `_buildHomeDashboard`, genre cards, filter chips, import banner | `views/sections/home_section.dart` → `HomeSection(isDesktop: …)` (shared; keep mobile edits inside `!isDesktop` / `isMobile` branches) |
| `_buildLibraryView` | `views/sections/library_section.dart` → `LibrarySection(isDesktop: …)` (shared, same rule) |
| `_buildPlaylistContent` (track list) | `views/sections/playlist_section.dart` → `PlaylistSection` (shared, same rule) |
| `_buildPersonalizeButton`, `_buildImportButton` | `views/sections/section_header_buttons.dart` → `PersonalizeButton`, `ImportPlaylistButton` |
| `_SpotifyPlaylistCard`, `_SpotifyQuickTile`, `_buildFallbackCover` | `widgets/spotify_playlist_card.dart`, `widgets/spotify_quick_tile.dart`, `widgets/playlist_fallback_cover.dart` (now public) |

Router (`views/symphony_player_screen.dart`) still owns: nav-history
recording, track pre-warm, the Home filter state (`_homeFilter`, passed into
`HomeSection` so it survives tab switches), and tab → section selection.

Rebasing mobile work: if you edited the old `!isDesktop` branches, re-apply
the hunk to `mobile/mobile_shell.dart` or `mobile/mobile_playlist_hero.dart`;
code bodies were moved verbatim except `mounted` → `context.mounted`.
Test: `test/player_shell_routing_test.dart` asserts 420px → MobileShell.

## 2026-10-10 — [desktop] Phase 0a: unified layout breakpoint

- New `lib/core/layout/breakpoints.dart`: `Breakpoints.desktop` (850),
  `Breakpoints.isDesktop(context)`, `Breakpoints.isMobile(context)`.
- Replaced the ad-hoc width literals: `symphony_player_screen.dart` (>= 850),
  `bottom_player_bar.dart` (< 750), `search_view.dart` and the playlist card /
  quick tile (< 700), `spotify_track_row.dart` (< 800).
- **Behavior change (intentional, fixes the known defect):** between 700 and
  850 px the bottom bar, track rows, search header and cards now render their
  mobile variant, matching the mobile shell (bottom nav) shown at that width.
- Mobile: use `Breakpoints.isMobile(context)` for any new width check; never
  compare `MediaQuery` widths to literals.
