import { spawn } from 'node:child_process';

const SEARCH_RESULTS = 5;
const LOOKUP_TIMEOUT_MS = 30_000;

/** Runs yt-dlp for lookups and audio, with the cookies and JS runtime set up once. */
export class YtDlp {
  constructor({ path = 'yt-dlp', cookiesFile = null, poTokens = false } = {}) {
    this.path = path;
    this.baseArgs = [
      '--no-warnings',
      // Lets yt-dlp solve YouTube's player challenges with this same Node.
      '--js-runtimes', `node:${process.execPath}`,
      ...(cookiesFile ? ['--cookies', cookiesFile] : []),
      // With the PO token helper running, also try the mobile web player:
      // the token gets it past the bot check on cloud servers.
      ...(poTokens ? ['--extractor-args', 'youtube:player_client=default,mweb'] : []),
    ];
  }

  /** The top few YouTube results for `query`, without fetching each video. */
  async search(query) {
    const data = await this.json(['--flat-playlist', `ytsearch${SEARCH_RESULTS}:${query}`]);
    return (data.entries ?? []).map(toVideo).filter(Boolean);
  }

  /** One video by its link. */
  async video(url) {
    const video = toVideo(await this.json(['--no-playlist', url]));
    if (!video) throw new Error('That video could not be found.');
    return video;
  }

  /** Every video in a YouTube playlist link. */
  async playlist(url) {
    const data = await this.json(['--flat-playlist', '--yes-playlist', url]);
    return { title: data.title ?? 'YouTube playlist', videos: (data.entries ?? []).map(toVideo).filter(Boolean) };
  }

  /**
   * Starts downloading a video's audio to stdout. The caller owns the process
   * and kills it when the song stops.
   */
  audio(url) {
    return spawn(this.path, [
      ...this.baseArgs,
      '-f', 'bestaudio[acodec=opus]/bestaudio',
      '--no-playlist',
      '--quiet',
      '-o', '-',
      url,
    ], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  }

  json(args) {
    return new Promise((resolve, reject) => {
      const child = spawn(this.path, [...this.baseArgs, '-J', ...args], {
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
      });
      let out = '';
      let err = '';
      const timer = setTimeout(() => child.kill(), LOOKUP_TIMEOUT_MS);
      child.stdout.setEncoding('utf8').on('data', (d) => { out += d; });
      child.stderr.setEncoding('utf8').on('data', (d) => { err += d; });
      child.on('error', (e) => {
        clearTimeout(timer);
        reject(e.code === 'ENOENT' ? new Error(`yt-dlp was not found at "${this.path}".`) : e);
      });
      child.on('close', (code) => {
        clearTimeout(timer);
        if (code !== 0) return reject(new Error(explainYtDlpError(err) ?? `yt-dlp failed (exit ${code}).`));
        try {
          resolve(JSON.parse(out));
        } catch {
          reject(new Error('yt-dlp returned something unreadable.'));
        }
      });
    });
  }
}

/** Turns a yt-dlp entry into the fields a song needs. */
export function toVideo(entry) {
  if (!entry?.id || !entry.title) return null;
  if (entry.title === '[Private video]' || entry.title === '[Deleted video]') return null;
  const channel = entry.channel ?? entry.uploader ?? '';
  return {
    id: entry.id,
    title: entry.title,
    channel,
    durationSec: Number.isFinite(entry.duration) ? Math.round(entry.duration) : null,
    url: `https://www.youtube.com/watch?v=${entry.id}`,
  };
}

/** A short reason a person can act on, from yt-dlp's error output. */
export function explainYtDlpError(stderr) {
  if (/confirm you.re not a bot|sign in to confirm/i.test(stderr)) {
    return 'YouTube is blocking this server (it asks to "confirm you\'re not a bot"). See the README.';
  }
  if (/requested format is not available/i.test(stderr)) {
    return 'YouTube offered no audio this bot can download.';
  }
  if (/private video/i.test(stderr)) return 'That video is private.';
  if (/video unavailable|not available/i.test(stderr)) return 'That video is not available.';
  if (/age/i.test(stderr) && /restricted|confirm your age/i.test(stderr)) {
    return 'That video is age-restricted. A cookies file from a signed-in account is needed.';
  }
  const line = stderr.split('\n').map((l) => l.trim()).find((l) => l.startsWith('ERROR:'));
  return line ? line.replace(/^ERROR:\s*/, '') : null;
}
