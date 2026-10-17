# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

## 2026-10-17 — [core] Online Jams through a relay

- Owner-approved exception to "no server on native": online Jams pass Jam
  messages (never audio) through `jam_relay/`, a Cloudflare Worker with one
  Durable Object per room. Wi-Fi Jams are unchanged and need no server.
- `jam_transport.dart`: `jamRelayUrl` (`--dart-define=SYMPHONY_JAM_RELAY`),
  `newOnlineJamCode()`, `isOnlineJamCode()`, `onlineJamExists()`,
  `hostOnlineJam(code, onLost:)`, `joinOnlineJam(code)`. Online codes are 6
  characters from `onlineJamCodeAlphabet`; Wi-Fi codes stay 4 digits.
- `JamController.host({online})`; `join(code:)` picks the transport by the
  code's shape and upper-cases it. `JamHosting.online`, `JamConnecting.online`,
  end reason `relay_lost`.
- Tests: `test/fake_jam_relay.dart` speaks the relay protocol on loopback;
  `jam_session_test.dart` runs every scenario over both transports.

## 2026-10-15 — [core] Join a Jam with just the code

- Guests type only the 4-digit code. `findLanJam(code)` broadcasts a UDP
  question on port 47853 (`jamDiscoveryPort`); the host's `JamBeacon` answers
  only for its own code with its TCP port. `JamController.join({code})`.
- `JamHosting` drops `port`/`addresses` and gains `discoverable` (false when
  the discovery port couldn't be opened). `parseJamAddress` is gone.
- Android: `CHANGE_WIFI_MULTICAST_STATE` and a `com.symphony.symphony/jam`
  channel in `MainActivity` that holds a Wi-Fi multicast lock while hosting,
  since some phones drop broadcasts otherwise.
- iOS can't find Jams by code: sending broadcasts needs Apple's restricted
  multicast entitlement.

## 2026-10-15 — [core] Jam UI, Phase 2

- `NowPlayingPanel.jam`: the desktop side panel has a Jam tab, and the player
  bar a Jam toggle. Mobile Now Playing has a Jam button next to Lyrics/Queue.
  The Home header has a `JamButton` (pill on desktop, icon on mobile), so a
  guest can join before anything plays. All hidden on web.
- `openJam(context, ref)` opens the right one for the layout;
  `JamPanel` is the shared content (start, join form, hosting, joined).
- `JamController.setGuestsControlPlayback(bool)`; guests get the change at
  once (new `permissions` message). `JamHosting`/`JamJoined` carry
  `permissions` and have `copyWith`.
- Home header rows now shrink instead of overflowing: the desktop buttons
  wrap, and the mobile title ellipsizes.
- Side panel tabs scroll horizontally (three tabs didn't fit in 340px).

## 2026-10-15 — [core] Jam (listen together on the same network), Phase 1

- New `lib/features/jam/`: protocol (`domain/`), LAN WebSocket transport,
  `JamHostService` / `JamGuestService`, and `jamProvider` (`JamController`:
  `host()`, `join(host:, port:, code:)`, `leave()`; state is `JamIdle`,
  `JamConnecting`, `JamHosting`, `JamJoined`). No UI yet; plan and UI split
  are in `.claude/coordination/JAM_PLAN.md`.
- `SymphonyAudioHandler`, additive: `remote` (`PlaybackRemote?`). While set
  (a Jam guest), `play/pause/seek/skip*/skipToQueueItem/enqueue/playNext/
  removeFromQueue/moveInQueue/playTrack/playQueue` go to the remote instead
  of playing here, shuffle/repeat changes are ignored, and a song that ends
  doesn't advance. Existing UI needs no change to work as a guest.
  Guests drive playback with `followQueue`, `followLoadCurrent`,
  `followPlaying`, `followSeek`. Also new: `resolvedVideoIdStream`,
  `position`, `isPlayingHere`.
- Audio interruptions and unplugging headphones now pause via an internal
  path, so on a guest they pause that device only, not the whole Jam.
- `AudioStreamResolverService.knownVideoId(track)`: the video a track plays
  from if already known (its `yt_` id or a trusted match). Never searches.

## 2026-10-12 — [core] Queue, shuffle/repeat, lyrics, onboarding, no starter playlists

- `CuratedPlaylists` is gone. `ImportedPlaylistsNotifier` starts empty and
  drops the four old starter ids (`legacyStarterIds`) from saved data.
  Home genre cards are searches now.
- Handler queue lives in `domain/play_queue.dart` (`PlayQueue`). The queue
  stream is always play order; `currentIndex` indexes into it. New:
  `playNext(track)`, `enqueue(track)`, `removeFromQueue(i)`,
  `moveInQueue(from, to)`, `skipToQueueItem(i)`, `setShuffleMode`,
  `setRepeatMode`. Both modes are reported in `PlaybackState`. With repeat
  off, playback stops after the last song (it used to wrap).
- Shared widgets: `ShuffleButton`/`RepeatButton`, `QueuePanel`,
  `features/lyrics` (`LyricsPanel`, LRCLIB, on-device). Desktop opens them
  in `NowPlayingSidePanel` via `nowPlayingPanelProvider`; mobile has
  `showMobileNowPlaying` (mini player tap / swipe up).
- `main.dart` loads `AppPrefs` before `runApp`: overrides
  `accentThemeProvider` (now saved on change) and
  `onboardingCompleteProvider` (defaults to true, so tests are unaffected).
- Update dialog uses `AppReleaseInfo.displayVersion` / `displayNotes`. CI
  writes release notes from feat/fix/perf commit subjects.

## 2026-10-12 — [core] Instant starts: remembered links + background prefetch

- `MatchIndex` entries are now `MatchEntry` (video id + stream link,
  expiry, duration, container); YouTube links last ~6 h and are IP-bound.
  A fresh link (>20 min left) resolves with no yt-dlp run. Bare-id entries
  from older files still load. `forgetTrack` drops the link, keeps the id.
- `AudioStreamResolverService.prefetch(tracks, replace:)` resolves in the
  background one at a time and pauses while the user waits on a resolve;
  `hasInstantSource(track)`. `preloadTracks` routes to it on native.
- Handler: next song still downloads; the 4 after it get links prefetched.
  Opening a playlist prefetches its first 5 (native).
- Windows `maxConcurrentRuns` 2 -> 3 so a tap always has a free slot.

## 2026-10-12 — [core] Accurate matching + faster starts

- `AudioExtractor.searchSong(query)` (all implementations; Android channel
  method `searchSong {query}` added to `YtDlpBridge.kt`; replies now include
  `id`, `title`, `channel`). `ExtractedAudio` gained `videoId/title/channel`.
- Resolver: remembered match → YouTube Music song search (verified) →
  fallback search. New `MatchIndex` (`matching/`), injectable via
  `matchIndex:`. `scoreVideoCandidate`: ±45 s hard limit (was 80), length
  dominates, version words (live/acoustic/remix/radio edit…) −120.
- Benchmark on a real 45-song playlist: see the commit message.
- Handler streams first (no headers) and saves the cache copy in the
  background; falls back to the copy if streaming fails.
- Windows: CI bundles the yt-dlp folder build in `Release\yt-dlp\`; the
  extractor prefers it and runs `-U` on it in place.
- Windows: one-time migration of `%APPDATA%\com.symphony\symphony` data to
  the new `Symphony\Symphony` folder (exe metadata rename in v1.0.27).

## 2026-10-11 — [core] Native playback from a local cache (fixes Windows hang after a song)

- Native (Windows + Android) now downloads each resolved stream into
  `PlaybackCache` (`<app support>/playback_cache`, 400 MB, oldest evicted)
  with `chunkedDownload` (1 MiB Range requests), then plays the `file://`
  copy. Remote streaming with headers went through just_audio's proxy on the
  UI isolate; that is gone on native. Web unchanged.
- `chunkedDownload` is also used by `OfflineDownloadService` (YouTube
  throttles a single full GET to ~real time: 60 s vs ~1 s ranged).
- Preloading on native: only the next track (resolve + cache); no launch-time
  warm-up; playlist open pre-resolves 1 track.
- `WindowsYtDlpExtractor.maxConcurrentRuns = 2`.

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

## 2026-10-11 — [mobile] yt-dlp on Android (branch `mobile/ytdlp-android`)

- Kotlin side of `com.symphony.symphony/ytdlp` is in
  `android/app/src/main/kotlin/com/symphony/symphony/YtDlpBridge.kt`, using
  `io.github.junkfood02.youtubedl-android:library:0.18.1` (yt-dlp 2025.11.12,
  Python 3.12, QuickJS for YouTube's JS challenges). Contract unchanged.
  - Library init runs once per process on a worker thread when the engine
    attaches; `isAvailable` waits for it.
  - `extract` runs `-f "ba[ext=m4a]/ba[acodec^=mp4a]/ba" --dump-json
    --no-playlist`, shares one run between concurrent calls for the same id,
    and kills yt-dlp after 90 s. Error codes: `bad_args`, `extract_failed`.
  - `update` updates from the stable channel (`update_failed` on error). The
    Kotlin side also runs it by itself at most once per 24 h after init.
- Dart: `AndroidYtDlpExtractor.update()` (returns null on failure),
  `@visibleForTesting AndroidYtDlpExtractor.channel`. `extract` now also maps
  `MissingPluginException` to `AudioStreamResolutionException`.
- APK: `jniLibs.useLegacyPackaging = true` (the library runs libpython/libqjs
  from nativeLibraryDir), x86 libs excluded. The universal release APK goes
  from 56.0 MB to 69.5 MB. CI is unchanged.
- Desktop: nothing to adapt.

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
