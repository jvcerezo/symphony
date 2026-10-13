import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import {
  AudioPlayerStatus,
  NoSubscriberBehavior,
  StreamType,
  VoiceConnectionStatus,
  createAudioPlayer,
  createAudioResource,
  entersState,
  joinVoiceChannel,
} from '@discordjs/voice';
import { SongQueue } from './queue.js';
import { matchSong } from './sources.js';
import { explainYtDlpError } from './ytdlp.js';

/** Songs in a row that may fail before the bot stops trying the rest. */
const MAX_FAILURES_IN_A_ROW = 3;
const ALONE_GRACE_MS = 2 * 60_000;

/**
 * Plays one server's queue in a voice channel.
 *
 * Events: `start(song)`, `failed(song, reason)`, `finished()`,
 * `gaveUp(reason)`, `left(reason)`.
 */
export class GuildPlayer extends EventEmitter {
  constructor({ guild, ytdlp, ffmpegPath = 'ffmpeg', maxQueue = 500, idleMinutes = 5 }) {
    super();
    this.guild = guild;
    this.ytdlp = ytdlp;
    this.ffmpegPath = ffmpegPath;
    this.idleMs = idleMinutes * 60_000;
    this.queue = new SongQueue({ maxLength: maxQueue });
    this.connection = null;
    this.textChannelId = null;
    this.procs = [];
    this.failures = 0;
    this.advancing = false;
    this.skipRequested = false;
    this.idleTimer = null;
    this.aloneTimer = null;

    this.audio = createAudioPlayer({ behaviors: { noSubscriber: NoSubscriberBehavior.Pause } });
    this.audio.on(AudioPlayerStatus.Idle, (old) => this.#onSongEnded(old.resource?.metadata));
    this.audio.on(AudioPlayerStatus.Playing, () => this.#clearIdleTimer());
    this.audio.on(AudioPlayerStatus.Paused, () => this.#startIdleTimer());
    this.audio.on('error', (e) => {
      const song = e.resource?.metadata;
      if (song) song.error ??= e.message;
    });
  }

  get channelId() {
    return this.connection?.joinConfig.channelId ?? null;
  }

  get isPaused() {
    return this.audio.state.status === AudioPlayerStatus.Paused;
  }

  get isPlaying() {
    return this.audio.state.status !== AudioPlayerStatus.Idle;
  }

  /** How far into the current song playback is, in seconds. */
  get positionSec() {
    const resource = this.audio.state.resource;
    return resource ? Math.floor(resource.playbackDuration / 1000) : 0;
  }

  /** Joins (or moves to) a voice channel and waits until audio can flow. */
  async join(channel) {
    if (this.connection && this.channelId === channel.id) return;
    this.connection?.destroy();
    const connection = joinVoiceChannel({
      channelId: channel.id,
      guildId: this.guild.id,
      adapterCreator: this.guild.voiceAdapterCreator,
      selfDeaf: true,
    });
    this.connection = connection;
    connection.subscribe(this.audio);
    connection.on(VoiceConnectionStatus.Disconnected, async () => {
      try {
        // Moved to another channel or a brief network drop: it reconnects.
        await Promise.race([
          entersState(connection, VoiceConnectionStatus.Signalling, 5_000),
          entersState(connection, VoiceConnectionStatus.Connecting, 5_000),
        ]);
      } catch {
        if (this.connection === connection) this.leave('Disconnected from the voice channel.');
      }
    });
    try {
      await entersState(connection, VoiceConnectionStatus.Ready, 20_000);
    } catch {
      if (this.connection === connection) this.leave(null);
      throw new Error('Could not connect to that voice channel. Check the bot can Connect and Speak there.');
    }
  }

  /** Adds songs; starts playing if nothing is. Returns how many were added. */
  add(songs, { next = false } = {}) {
    const added = this.queue.add(songs, { next });
    if (added > 0 && !this.isPlaying && !this.advancing) void this.#playNext();
    else if (added > 0) this.#prepareNext();
    return added;
  }

  skip() {
    if (!this.isPlaying) return false;
    this.skipRequested = true;
    this.audio.stop(true);
    return true;
  }

  pause() {
    return this.audio.pause();
  }

  resume() {
    return this.audio.unpause();
  }

  /** Empties the queue and leaves the voice channel. */
  stop() {
    this.leave(null);
  }

  leave(reason) {
    const connection = this.connection;
    // Cleared first so the player going idle below does not start the next song.
    this.connection = null;
    this.failures = 0;
    this.queue.clear();
    this.#killProcs();
    this.audio.stop(true);
    this.#clearIdleTimer();
    this.setAlone(false);
    if (connection && connection.state.status !== VoiceConnectionStatus.Destroyed) connection.destroy();
    this.emit('left', reason);
  }

  /** Called when the listeners in the bot's channel change. */
  setAlone(alone) {
    if (!alone) {
      clearTimeout(this.aloneTimer);
      this.aloneTimer = null;
    } else if (!this.aloneTimer) {
      this.aloneTimer = setTimeout(() => this.leave('Everyone left, so I left too.'), ALONE_GRACE_MS);
    }
  }

  #onSongEnded(song) {
    this.#killProcs();
    if (!this.connection || this.advancing) return;
    const skipped = this.skipRequested;
    this.skipRequested = false;
    if (song?.error && !skipped) {
      this.emit('failed', song, song.error);
      if (++this.failures >= MAX_FAILURES_IN_A_ROW) return this.#giveUp();
      return void this.#playNext({ skipped: true });
    }
    void this.#playNext({ skipped });
  }

  async #playNext({ skipped = false } = {}) {
    this.advancing = true;
    try {
      for (;;) {
        const song = this.queue.advance({ skipped });
        if (!song) {
          this.emit('finished');
          this.#startIdleTimer();
          return;
        }
        delete song.error;
        try {
          await matchSong(song, this.ytdlp);
        } catch (e) {
          this.emit('failed', song, e.message);
          if (++this.failures >= MAX_FAILURES_IN_A_ROW) return this.#giveUp();
          skipped = true;
          continue;
        }
        if (!this.connection) return;
        this.#stream(song);
        this.emit('start', song);
        this.#prepareNext();
        return;
      }
    } finally {
      this.advancing = false;
    }
  }

  #giveUp() {
    this.failures = 0;
    this.queue.clear();
    this.emit('gaveUp', `${MAX_FAILURES_IN_A_ROW} songs in a row would not play, so I stopped. YouTube may be blocking this server.`);
    this.#startIdleTimer();
  }

  /** Matches the next song early so it starts without a gap. */
  #prepareNext() {
    const next = this.queue.upcoming[0];
    if (next && !next.url) matchSong(next, this.ytdlp).catch(() => {});
  }

  /** yt-dlp downloads the audio, ffmpeg turns it into Discord's Opus format. */
  #stream(song) {
    this.#killProcs();
    const source = this.ytdlp.audio(song.url);
    const ffmpeg = spawn(this.ffmpegPath, [
      '-hide_banner', '-loglevel', 'error',
      '-i', 'pipe:0',
      '-vn', '-ac', '2', '-ar', '48000',
      '-c:a', 'libopus', '-b:a', '128k',
      '-f', 'ogg', 'pipe:1',
    ], { stdio: ['pipe', 'pipe', 'ignore'], windowsHide: true });
    const procs = [source, ffmpeg];
    this.procs = procs;

    let stderr = '';
    source.stderr.setEncoding('utf8').on('data', (d) => { stderr += d; });
    source.on('error', (e) => { song.error ??= e.code === 'ENOENT' ? 'yt-dlp is not installed on the bot.' : e.message; });
    source.on('close', (code) => {
      if (code !== 0 && !source.stoppedByUs) song.error ??= explainYtDlpError(stderr) ?? 'The audio download failed.';
    });
    ffmpeg.on('error', (e) => { song.error ??= e.code === 'ENOENT' ? 'ffmpeg is not installed on the bot.' : e.message; });
    for (const stream of [source.stdout, ffmpeg.stdin, ffmpeg.stdout]) stream.on('error', () => {});
    source.stdout.pipe(ffmpeg.stdin);
    ffmpeg.stdout.once('data', () => { this.failures = 0; });

    const resource = createAudioResource(ffmpeg.stdout, { inputType: StreamType.OggOpus, metadata: song });
    this.audio.play(resource);
  }

  #killProcs() {
    for (const p of this.procs) {
      p.stoppedByUs = true;
      if (p.exitCode === null) p.kill();
    }
    this.procs = [];
  }

  #startIdleTimer() {
    this.#clearIdleTimer();
    this.idleTimer = setTimeout(() => this.leave('Nothing playing for a while, so I left.'), this.idleMs);
  }

  #clearIdleTimer() {
    clearTimeout(this.idleTimer);
    this.idleTimer = null;
  }
}
