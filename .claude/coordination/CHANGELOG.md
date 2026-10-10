# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

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
