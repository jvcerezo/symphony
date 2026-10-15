# Jam: listen together on the same network

Status: Phase 1 core built on `shared/jam-core` (2026-10-15); UI not started. Read `symphony-core` first; this plan follows its
ownership map and coordination protocol.

## What it is

One device **hosts** a Jam. Other Symphony apps on the same Wi-Fi/LAN **join**
it. Everyone hears the same song at the same moment, and guests can add songs to
the shared queue. Like Spotify's in-person Jam.

Fully on-device, so the "no server on native" rule holds: the host's app opens
a small WebSocket server, and each guest still finds and streams its own audio.
**Only playback state crosses the network, never audio.**

Out of scope for v1: web builds (a browser can't host, and an `https` page can't
open `ws://` to a LAN address), voting, chat. Jams across the internet come
in Phase 4 as a second `JamTransport`. Keep the protocol and services
transport-agnostic so Phase 4 doesn't touch them.

## Model

- **The host decides.** The host's `SymphonyAudioHandler` is the real player.
  Guests send *requests*; the host applies them and broadcasts the new *state*.
  Guests never change their own queue directly while in a Jam.
- **Same upload everywhere.** The host sends each track with the YouTube video
  id it resolved to (`ResolvedAudioStream.sourceVideoId`). Guests build the
  track with id `yt_<videoId>`, which the resolver already treats as a known
  video, so guests skip song matching and play the identical audio.
- **Room code.** The host shows a 4-digit code; `hello` must carry it. This
  stops stray devices on a café/dorm network from joining.

## Protocol (JSON over WebSocket, `v: 1`)

| Direction | Message | Fields |
|---|---|---|
| guest → host | `hello` | `v`, `code`, `name` |
| host → guest | `welcome` | `guestId`, `state`, `members`, `permissions` |
| host → guest | `reject` | `reason` (`bad_code`, `full`, `version`) |
| guest → host | `ping` | `t0` (guest clock, ms) |
| host → guest | `pong` | `t0`, `hostT` |
| host → all | `state` | `rev`, `queue: [JamTrack]`, `index`, `playing`, `positionMs`, `atHostMs`, `repeat`, `shuffle` |
| guest → host | `request` | `kind` (`add`, `playNext`, `remove`, `move`, `play`, `pause`, `seek`, `next`, `previous`, `jump`), plus `track` / `index` / `from` / `to` / `positionMs` |
| host → all | `members` | `[{guestId, name}]` |
| either | `bye` | `reason` |

`JamTrack` = `title`, `artist`, `album?`, `durationMs?`, `artworkUrl?`, `videoId?`, `sourceId` (the host's original `Track.id`).

The host sends `state` on every queue/track/play/pause/seek change, plus a
heartbeat every 5 s. `rev` only goes up, and guests drop anything older.

## Sync

- **Clock offset**: on join, the guest sends 6 `ping`s. It keeps the sample
  with the lowest round trip: `offset = hostT - (t0 + rtt / 2)`. It re-syncs
  every 30 s and after any state gap over 10 s.
- **Where the host is now**: `expected = positionMs + (hostNow - atHostMs)` when
  `playing`, where `hostNow = localNow + offset`.
- **Drift policy** (checked every 2 s on the guest): if |actual - expected| > 300 ms,
  seek to `expected + seekLatencyEstimate`. Ignore smaller drift. Don't seek
  again within 3 s of a seek, so the guest doesn't keep jumping.
- **Track changes**: the guest loads the new track, then seeks to *where the host
  is now*, not to 0. A slow resolve means the guest joins a few seconds in
  instead of making everyone wait. Guests prefetch the next 2 queue items as soon
  as `state` arrives (`preloadTracks`), so this is usually instant.
- **Guest auto-advance is off**: when a song ends on a guest, it waits for the
  host's next `state` instead of advancing by itself.

## Code layout

```
lib/features/jam/
  domain/
    jam_message.dart        sealed JamMessage + toJson/fromJson          (Shared)
    jam_track.dart          JamTrack <-> Track mapping (yt_ ids)          (Shared)
    jam_state.dart          JamState, JamPermissions, JamMember           (Shared)
    clock_sync.dart         pure offset estimator                         (Shared)
    drift_policy.dart       pure: (actual, expected, lastSeek) -> action  (Shared)
  data/
    jam_transport.dart      abstract JamServer / JamConnection            (Shared)
    jam_transport_io.dart   dart:io HttpServer + WebSocketTransformer      (Shared)
    jam_transport_stub.dart web: isSupported = false                      (Shared)
    jam_discovery.dart      (+ _io via bonsoir, _stub) "_symphony-jam._tcp" (Shared)
    jam_host_service.dart   handler streams -> state; requests -> handler (Shared)
    jam_guest_service.dart  connect, clock sync, drive handler, drift loop (Shared)
  presentation/
    jam_providers.dart      jamSessionProvider (idle | hosting | joined)  (Shared)
    desktop/jam_panel.dart  host/join UI in the now-playing side panel    (Desktop)
    mobile/jam_sheet.dart   host/join bottom sheet                        (Mobile)
```

No new package for the socket itself: `dart:io` `HttpServer` and `WebSocket`
cover host and guest. One new dependency: **`bonsoir`** (mDNS) for the
"Jams nearby" list. Check that it builds for Windows, Android, macOS and iOS
before adding it, and keep it behind `jam_discovery_io.dart` so
`flutter build web` stays green. If it fails on any platform, fall back to
the manual-join path below and drop discovery from v1.

**Manual join (always available)**: the host panel shows `IP:port` + code;
the join dialog accepts it typed in. A QR code can come later.

### Changes to existing Shared files (claim them first)

- `symphony_audio_handler.dart`, additive only (as built):
  - `PlaybackRemote? remote`: while set, the user's actions (play, pause,
    seek, skips, jump, queue edits, `playTrack`/`playQueue` = play next +
    skip) go to the remote, shuffle/repeat changes are ignored, and a song
    that ends waits instead of advancing. So the existing UI works for a
    guest unchanged.
  - `followQueue`, `followLoadCurrent({startAt, play})`, `followPlaying`,
    `followSeek`: how the guest service drives playback, bypassing `remote`.
  - `resolvedVideoIdStream`, `position`, `isPlayingHere`.
- `audio_stream_resolver_service.dart`: `knownVideoId(track)` so the host
  can send video ids for upcoming songs, not just the current one.
- `pubspec.yaml`: `bonsoir`, still to do (see below).
- `main.dart`: nothing, unless providers need an override.

## Platform config

| Platform | Owner | Change |
|---|---|---|
| Android | Mobile | `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`; hold a `MulticastLock` while browsing (bonsoir may do it, check) |
| iOS | Mobile | `Info.plist`: `NSLocalNetworkUsageDescription`, `NSBonjourServices` = `_symphony-jam._tcp` |
| macOS | Desktop | `Release.entitlements`: add `com.apple.security.network.server` (only Debug has it today) |
| Windows | Desktop | First host triggers the Defender Firewall prompt. Bind on `anyIPv4`, explain the prompt in the host panel, and handle "no guests can connect" with a hint |

## Phases

**1. Core (Shared, branch `shared/jam-core`, one agent)**: done except discovery.
Not done yet: `jam_discovery` / `bonsoir` (needs per-platform build checks).
Until then, joining is manual: IP:port + code. Also open: changing
`permissions` while hosting isn't sent to guests yet (only in `welcome`).
Domain + transport + host/guest services + handler hooks. No UI.
Tests (`test/jam_*_test.dart`):
- message JSON round-trip for every type; unknown `kind`/`v` rejected
- `clock_sync`: picks lowest-RTT sample; offset math with fake clocks
- `drift_policy`: below / above threshold, seek cool-down
- host service with a fake handler: each `request` kind -> correct handler call, `rev` increments, bad code rejected
- **loopback**: real `HttpServer` on `127.0.0.1:0`, host + 2 guests, add/skip/pause round trip, guest `remoteControlled` set/cleared on join/leave

**2. UI (parallel, after 1 merges)**
- Desktop `desktop/jam-ui`: "Start a Jam" / "Join" in the now-playing panel;
  member list, code, IP:port; guest view shows "Jamming with <host>" and
  routes transport buttons through requests. macOS entitlement, firewall hint.
- Mobile `mobile/jam-ui`: same flows in a bottom sheet; Android/iOS config.
- Both: loading (connecting / syncing clock), error (host unreachable, bad
  code, host ended Jam), empty ("no Jams nearby") states.

**3. Tuning (both, on real devices)**
Two physical devices on one Wi-Fi, ideally Windows host + Android guest and the reverse.

**4. Online Jams (after 3 is stable)**
See "Phase 4: Jams over the internet" below.

## Phase 4: Jams over the internet

### Why a relay

Over the internet, a guest usually can't connect directly into the host:
most Philippine ISPs (Globe, PLDT, Converge, mobile data) put users behind
CGNAT, so port forwarding and UPnP don't help. WebRTC peer-to-peer still needs
a signaling server and, under CGNAT, often a TURN relay, so it saves nothing
and adds `flutter_webrtc`. Instead, **host and guests all connect outward
to a relay** that forwards Jam messages within a room. Outbound connections get
through any NAT.

### Rule exception (owner-approved 2026-10-15)

> Native builds may connect to a Symphony-hosted relay **only for online
> Jams**, and only after the user starts or joins one. Song search,
> streaming, downloads and LAN Jams stay fully on-device. If the relay is
> unreachable, the app shows "Online Jam unavailable" and everything else
> keeps working.

When Phase 4 merges, add this exception to the "No server on native" rule in
`.claude/skills/symphony-core/SKILL.md` (Shared change, claim it).

### Relay: a `/jam` endpoint on `server.dart`

No new DNS or service. The relay is a WebSocket route on the existing
`server.dart`, reached at `wss://symphony-api.jettimothycerezo.dev/jam/...`
through the same Cloudflare tunnel (tunnels pass WebSockets through). It's
written in Dart, so the envelope type can live in a small file that both the
server and the app use (`lib/features/jam/domain/jam_envelope.dart`, no Flutter
imports; `server.dart` already imports from outside `lib/` the same way, or
copy it if the server build can't reach it).

- **The app creates rooms, not the server.** The host generates `room` (8
  chars from an unambiguous alphabet, no `0/O/1/I/L`) and a random
  `hostToken`, and keeps both for the whole Jam. The server registers a room
  the first time a host connects with them. So when the server restarts and
  drops its in-memory rooms, the host reconnects, re-registers the same room,
  and guests reconnect with the code they already have.
- `GET /jam/<room>?role=host&token=…` and `?role=guest&name=…`, upgraded with
  `WebSocketTransformer`. A guest connecting before the host gets a
  `waiting_for_host` notice and stays connected (up to 60 s).
- Forwarding: guest → host only (tagged with `guestId`); host → one guest or
  everyone. Guests never see each other's raw messages. The relay doesn't parse
  Jam messages beyond the envelope `{to?, from?, body}`.
- Limits: 8 guests, 64 KB per message, 20 messages/s per socket, 10 new rooms
  per hour per IP. Forget a room 60 s after the host disconnects, or after 12 h.
  Ping idle sockets every 25 s so the tunnel doesn't close them.
- Keep it isolated inside one process: all relay code in a `_JamRelay` class
  with its own try/catch per socket, so a bad message can't affect `/api/*`
  handlers.
- Privacy: no message bodies or names in logs. Nothing is written to disk.
- **Single instance:** rooms live in memory, so online Jams must always use
  `ServerConfig.productionOrigin`, never the Render/Koyeb copies. If those
  ever become load-balanced or multi-instance, the relay needs shared state
  first.
- Clock sync goes through the relay unchanged. `pong.hostT` is the host's clock,
  and the lowest-RTT sample absorbs the extra hop.

Relay URL: `ServerConfig.jamRelayOrigin`, defaulting to `productionOrigin`
(`wss://` scheme) and overridable with `--dart-define=SYMPHONY_JAM_RELAY=…` for
a local `dart run server.dart`.

### Client

- `lib/features/jam/data/jam_transport_relay.dart`: `RelayJamServer` /
  `RelayJamConnection` implementing the Phase 1 interfaces. Uses
  `dart:io` `WebSocket` on native (the relay is `wss://`, so a web build could
  join later). Reconnects with backoff. The host keeps its `hostToken` in memory
  only.
- With the relay, the room code replaces the 4-digit LAN code, so `hello.code`
  is skipped. `room` + relay auth do that job.
- Host UI: "Start a Jam" offers **Nearby** (LAN) or **Online** (relay).
  Online shows the room code, a copy-link button and the member list.
- Invites:
  - Deep link `symphony://jam/<room>`: Android intent filter (Mobile), Windows
    protocol registration in the installer/first run (Desktop), iOS/macOS
    URL types (Mobile/Desktop).
  - `https://symphony.jettimothycerezo.dev/jam/<room>`: landing page route
    with "Open in Symphony" plus download buttons (Desktop owns `landing/`).
  - Discord: while hosting an online Jam, add `party` (id = room, size) and
    `secrets.join` to the Rich Presence activity in `discord_activity.dart`, so
    friends get **Ask to Join**. Handle the `ACTIVITY_JOIN` event in
    `discord_presence_io.dart` (Desktop).
- Guests on mobile data: same 300 ms drift threshold. Expect more re-seeks;
  only change the threshold if testing shows constant seeking.

### Tests

- Relay: start `_JamRelay` on `127.0.0.1:0` in a test. Host registers; guest
  joins; forwarding is directional; wrong host token rejected; 9th guest
  rejected; rate limit; guest waits for a late host; **room survives a relay
  restart** (new relay instance, host re-registers, guest reconnects).
- Client: `jam_transport_relay_test.dart` against that same real relay,
  reusing the Phase 1 loopback scenarios so both transports pass the same
  tests.
- CI: the existing analyze/test job covers it. Nothing new to deploy; it ships
  with `server.dart`.

### Done when

- Two devices on **different networks** (e.g. home Wi-Fi + mobile data) Jam
  with the same in-sync, request and host-leaves results as the LAN criteria.
- Relay down → "Online Jam unavailable", LAN Jam and normal playback unaffected.
- Invite link and Discord Ask to Join both land a guest in the room.

## Defaults (change if the owner wants)

- Guests may: add, play next, play/pause, skip. Host toggle "Only I control playback".
- Max 8 guests.
- Host leaves / app closes -> Jam ends; guests keep their copy of the queue and stop following.
- Guest leaves -> its handler goes back to normal (`remoteControlled = false`).

## Done when

- `flutter analyze`, `flutter test`, `flutter build windows`, `flutter build apk`, `flutter build web` all pass.
- On two real devices: join takes under 3 s; after a track change with prefetch, guests are audibly in sync (< 300 ms) within 2 s; skip/add/pause from a guest shows up on everyone within 1 s; killing the host's Wi-Fi leaves guests playing with a "Jam ended" notice.