# Shared API change log

Newest first. Note what changed in Shared code and how the other side should adapt.

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
