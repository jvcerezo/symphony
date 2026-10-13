import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

/** Reads the bot's settings from the environment (or `.env` via `npm start`). */
export function loadConfig(env = process.env) {
  const token = env.DISCORD_TOKEN?.trim();
  if (!token) {
    throw new Error('DISCORD_TOKEN is not set. Copy .env.example to .env and fill it in.');
  }
  return {
    token,
    // A private bot: any other server that adds it is left straight away.
    allowedGuildIds: list(env.ALLOWED_GUILD_IDS),
    ytDlpPath: env.YTDLP_PATH?.trim() || 'yt-dlp',
    ffmpegPath: env.FFMPEG_PATH?.trim() || 'ffmpeg',
    cookiesFile: cookiesFile(env),
    idleMinutes: number(env.IDLE_MINUTES, 5),
    maxQueue: number(env.MAX_QUEUE, 500),
    // The PO token helper's main.js; the Docker image sets this.
    potServerScript: env.POT_SERVER_SCRIPT?.trim() || null,
  };
}

function list(value) {
  return (value ?? '').split(',').map((s) => s.trim()).filter(Boolean);
}

function number(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/**
 * YouTube often asks cloud servers to sign in. A cookies.txt from a signed-in
 * browser gets past that: give its path, or its contents as base64 (handy for
 * a hosting secret).
 */
function cookiesFile(env) {
  if (env.YTDLP_COOKIES_FILE?.trim()) return env.YTDLP_COOKIES_FILE.trim();
  const b64 = env.YTDLP_COOKIES_B64?.trim();
  if (!b64) return null;
  const path = join(mkdtempSync(join(tmpdir(), 'symphony-bot-')), 'cookies.txt');
  writeFileSync(path, Buffer.from(b64, 'base64'), { mode: 0o600 });
  return path;
}
