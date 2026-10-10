# Shared-file claims

Add a line before editing a Shared file (see `.claude/skills/symphony-core`).
Remove it when your branch merges.

Format: `- [desktop|mobile] <file or symbol> — <why> — <YYYY-MM-DD>`

- [desktop] lib/core/layout/breakpoints.dart (new) + width literals in bottom_player_bar, spotify_track_row, search_view, symphony_player_screen — Phase 0a unified breakpoint — 2026-10-10
- [desktop] lib/features/audio_player/presentation/views/symphony_player_screen.dart — Phase 0b split into router + desktop/ + mobile/ shells + views/sections/ — 2026-10-10
- [desktop] lib/core/config/server_config.dart (new) + origin lists in audio_player_providers, offline_provider, audio_stream_resolver_service, spotify_embed_scraper_service, symphony_audio_handler host check — Phase 0c — 2026-10-10
- [desktop] search_view.dart (focusNode on query field) + bottom_player_bar.dart desktop volume branch — keyboard shortcuts — 2026-10-10
