# Symphony Discord bot

Plays music in a Discord voice channel for everyone in it. Give it a song name, a YouTube link, or a Spotify or YouTube playlist, the same links the Symphony app imports.

Commands start with `s!`, so they don't clash with other music bots' `/play`.

| Command | What it does |
| --- | --- |
| `s!play <song or link>` (`s!p`) | Joins your voice channel and plays it, or adds it to the queue |
| `s!playnext <song or link>` | Plays it right after the current song |
| `s!skip` (`s!s`), `s!pause`, `s!resume` | What they say. The "Now playing" message has these as buttons too |
| `s!stop` | Clears the queue and leaves |
| `s!queue [page]` (`s!q`) | What's coming up |
| `s!np` | The current song and how far in it is |
| `s!shuffle` | Shuffles the songs still to come |
| `s!remove <number>` | Takes a song out of the queue (numbers are from `s!queue`) |
| `s!loop off / song / queue` | Repeats the song or the whole queue |
| `s!help` | Lists the commands |

Only people in the bot's voice channel can control it. It leaves after 5 minutes with nothing playing, or 2 minutes after everyone else has left.

## 1. Create the bot in Discord

1. Open <https://discord.com/developers/applications> and click **New Application**. Name it "Symphony".
2. Go to **Bot**:
   - Click **Reset Token** and copy the token. This is `DISCORD_TOKEN`. Keep it secret; anyone with it controls the bot.
   - Under **Privileged Gateway Intents**, turn on **Message Content Intent**. The bot needs it to read `s!` commands; without it, it can't log in.
   - **Public Bot** on lets anyone with the invite link add it; off, only you can.
3. Start the bot (step 2 or 3 below). It prints an **Invite link**. Open it and pick your server.

## 2. Run it on your PC

Needs Node 22.9 or newer, [yt-dlp](https://github.com/yt-dlp/yt-dlp) and ffmpeg on PATH (`winget install yt-dlp.yt-dlp Gyan.FFmpeg`).

```sh
cd discord_bot
cp .env.example .env   # then fill in DISCORD_TOKEN
npm install
npm start
```

This is the most reliable way to run it: YouTube trusts a home connection. The music stops when the PC sleeps or the window closes.

## 3. Run it 24/7 on a host

Each push to `main` publishes the image `ghcr.io/jvcerezo/symphony-discord-bot:latest`. Run it anywhere that runs containers, such as Render, Koyeb, Fly.io or a small VPS:

```sh
docker run -d --restart unless-stopped \
  -e DISCORD_TOKEN=... -e ALLOWED_GUILD_IDS=... \
  ghcr.io/jvcerezo/symphony-discord-bot:latest
```

Set `ALLOWED_GUILD_IDS` to your server's ID so the bot leaves any other server it is added to. If the host needs a web port (Render's "Web Service", for example), set `PORT`; the bot then answers health checks on it. A host that puts free services to sleep will cut the music off, so it needs one that stays on.

### When YouTube blocks the server

YouTube often answers cloud machines with "Sign in to confirm you're not a bot". The Docker image deals with this itself: it runs a PO token helper ([bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)) beside the bot. The helper makes the proof YouTube asks for, so no account is needed. It uses about 200 MB of extra memory, which still fits in a 512 MB free plan.

If the bot still says YouTube is blocking it, cookies from a signed-in account are the last resort. They don't work with every account: YouTube serves some accounts, often new ones, a streaming format yt-dlp can't download yet.

1. Use a spare Google account, not your main one. YouTube can flag accounts used this way.
2. Sign in to YouTube in a private window, open `https://www.youtube.com/robots.txt` in the same window, and export cookies with the "Get cookies.txt LOCALLY" extension (Netscape format). Then close the private window without signing out.
3. Give the bot the file, either as a path (`YTDLP_COOKIES_FILE`) or its contents in base64 (`YTDLP_COOKIES_B64`; on Windows: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cookies.txt"))`).

Every CI run reports, in the "Check YouTube Audio From a Cloud Machine" step, whether a cloud machine can download audio without help right now.

## Notes

- Keep it a private bot for your own servers. Large public music bots have been shut down over YouTube's terms.
- Spotify links are read from Spotify's public embed page, like the app's import. Each song is matched to YouTube just before it plays, preferring the version whose length matches Spotify's. Very long playlists may stop at the first 100 songs.
- The bot does not see the app's local playlists. Share a Spotify or YouTube playlist link instead.
- Tests: `npm test`.
