# Shared-file claims

Add a line before editing a Shared file (see `.claude/skills/symphony-core`).
Remove it when your branch merges.

Format: `- [desktop|mobile] <file or symbol> — <why> — <YYYY-MM-DD>`


- [mobile] lib/main.dart AudioServiceConfig.androidNotificationIcon — point at new monochrome drawable/ic_stat_symphony (adaptive mipmap is unsafe as a small icon) — 2026-10-10
- [mobile] lib/features/audio_player/data/services/symphony_audio_handler.dart — request Android 13+ POST_NOTIFICATIONS at first playback (additive ctor param) — 2026-10-10
