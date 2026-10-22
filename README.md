# Symphony

A minimalist music player for Windows, Android and the web. Bring your playlists from the app you already use, or search for any song, and Symphony plays the full track.

Landing page: <https://symphony.jettimothycerezo.dev> · Downloads: [GitHub Releases](https://github.com/jvcerezo/symphony/releases/latest)

## What it does

- **Import playlists** by pasting a playlist link, or search songs by name.
- **Plays the real song.** Each track is matched to the version whose length matches the original, skipping live, remix and cover versions. Matches are remembered.
- **Works offline.** Download songs or whole playlists; songs you play are cached too.
- **Jam** with friends: one device hosts, others join with a code and hear the same song at the same moment. Works on the same Wi-Fi, or online through a small relay. Only playback state is shared, never audio.
- **Synced lyrics** that follow along as the song plays.
- **Feels at home on each platform:** media keys, lock-screen and notification controls, system tray and keyboard shortcuts on Windows, Discord status, and in-app updates.

## No server needed

The Windows and Android apps find, stream and download audio entirely on your device with [yt-dlp](https://github.com/yt-dlp/yt-dlp). Nothing runs on a Symphony server, so there is nothing to host or sign up for.

The only exception is the web build: a browser can't run yt-dlp, so the web player needs `server.dart` (see [Self-hosting the web player](#self-hosting-the-web-player)). The public site is just the landing page.

## Install

| Platform | Download | Notes |
| --- | --- | --- |
| Windows (x64) | `symphony-windows-x64.zip` | Unzip and run `symphony.exe`. Updates itself. |
| Android | `symphony.apk` | Allow installs from your browser. Every release is signed with the same key, so updates install over the old version. |
| macOS | `symphony-macos.zip` | Not notarized: right-click the app and choose **Open** the first time. |
| iOS | `symphony-ios.ipa` | Unsigned. Sideload it with your own Apple ID (Sideloadly, AltStore). |

All builds are on the [latest release](https://github.com/jvcerezo/symphony/releases/latest).

## Repository layout

```
lib/                 the Flutter app (one codebase for every platform)
  core/              theme, layout breakpoints, config, platform services
  features/
    audio_player/    playback, queue, song matching, offline downloads, player UI
    playlist_import/ playlist link importers
    metadata_search/ search and artwork
    jam/             listen-together sessions (LAN and online)
    lyrics/          synced lyrics
    browse/          genre playlists
    landing/         web landing page
test/                Flutter tests
server.dart          backend for the web player only
jam_relay/           Cloudflare Worker that relays online Jams
discord_bot/         a Discord music bot built on the same sources (own README)
```

## Development

Needs the Flutter SDK (stable, Dart 3.5+).

```sh
flutter pub get
flutter run -d windows        # or an Android device id from `flutter devices`
flutter test
flutter analyze
```

On Windows the app runs yt-dlp from a `yt-dlp\` folder next to `symphony.exe` (CI bundles the official folder build there) and updates it daily. For a local build, unzip [`yt-dlp_win.zip`](https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_win.zip) into `build\windows\x64\runner\<Debug|Release>\yt-dlp\`; without it, playback falls back to a slower pure-Dart extractor. The macOS app downloads yt-dlp on first start, and Android uses a bundled one through `youtubedl-android`.

Build-time options, passed with `--dart-define`:

| Name | What it does |
| --- | --- |
| `SYMPHONY_SERVER=https://host` | Point the app at a specific `server.dart` (native apps use none by default) |
| `SYMPHONY_WEB_DEMO=true` | Turn on the in-browser player (off for the landing page) |
| `SYMPHONY_JAM_RELAY=wss://host` | Use a different Jam relay |
| `SYMPHONY_VERSION=1.0.N` | Version shown in the app and compared against releases for updates; CI sets it |

### Web and the backend

```sh
dart run server.dart                                   # backend on :8080
flutter run -d chrome --web-port 5000 --dart-define=SYMPHONY_WEB_DEMO=true --dart-define=SYMPHONY_SERVER=http://localhost:8080
```

Open the page and append `#player` for the player. From an Android emulator the local backend is at `http://10.0.2.2:8080`.

### Jam relay

```sh
cd jam_relay
npm test
npm run deploy    # deploys to Cloudflare with wrangler; done by hand, not by CI
```

## Self-hosting the web player

The Docker image builds the web app and serves it from `server.dart`, with yt-dlp installed:

```sh
docker compose up -d     # http://localhost:8080
```

Resolved songs are cached in the `symphony-cache` volume. Each push to `main` also publishes the image to GHCR.

## CI and releases

`.github/workflows/deploy.yml` runs on `main`, `v*` tags and `desktop/**`, `mobile/**`, `shared/**` branches. It analyzes and tests, then builds web, Android, Windows, macOS and iOS. Pushes to `main` also:

- publish a GitHub Release titled with the build version (`1.0.<run number>`), with release notes from `feat`/`fix`/`perf` commits since the last one; the apps read this to offer updates
- deploy the landing page to GitHub Pages
- publish the server and Discord bot images to GHCR, and trigger Render/Koyeb deploys if their secrets are set

Android release signing needs the `ANDROID_KEYSTORE_BASE64` and related secrets; branch builds without them fall back to debug signing.

Commits follow [Conventional Commits](https://www.conventionalcommits.org) (`feat(jam): …`, `fix(ui): …`), since release notes are built from them.
