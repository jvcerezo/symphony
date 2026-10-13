/**
 * One server's song list. Pure state, no Discord or audio, so it can be tested
 * on its own. Songs already played stay in the list so "loop queue" can go
 * round again.
 *
 * A song is `{ title, artist, durationSec, url, requestedBy }`; `url` is null
 * until the song is matched to a YouTube video, right before it plays.
 */
export class SongQueue {
  constructor({ maxLength = 500 } = {}) {
    this.maxLength = maxLength;
    this.songs = [];
    /** The song playing, or the last one played once the list has run out. */
    this.index = -1;
    this.ended = false;
    /** 'off' | 'song' | 'queue' */
    this.loop = 'off';
  }

  get current() {
    return this.ended ? null : (this.songs[this.index] ?? null);
  }

  /** Songs still to come, in order. */
  get upcoming() {
    return this.songs.slice(this.index + 1);
  }

  get isEmpty() {
    return this.current === null && this.upcoming.length === 0;
  }

  /**
   * Adds songs to the end, or straight after the current one with `next`.
   * Returns how many fit under the length limit.
   */
  add(songs, { next = false } = {}) {
    const room = Math.max(0, this.maxLength - this.upcoming.length);
    const added = songs.slice(0, room);
    const at = next ? this.index + 1 : this.songs.length;
    this.songs.splice(at, 0, ...added);
    return added.length;
  }

  /**
   * Moves to the song that plays next and returns it, or null at the end.
   * A song on repeat plays again unless it was skipped.
   */
  advance({ skipped = false } = {}) {
    if (this.loop === 'song' && !skipped && this.current) return this.current;
    this.ended = false;
    if (this.index + 1 < this.songs.length) {
      this.index += 1;
      return this.current;
    }
    if (this.loop === 'queue' && this.songs.length > 0) {
      this.index = 0;
      return this.current;
    }
    this.ended = true;
    return null;
  }

  /** Removes the song at `position` in the upcoming list (1 = next). */
  remove(position) {
    if (!Number.isInteger(position) || position < 1 || position > this.upcoming.length) return null;
    return this.songs.splice(this.index + position, 1)[0];
  }

  /** Shuffles the songs still to come; the playing one stays put. */
  shuffle(random = Math.random) {
    const rest = this.upcoming;
    for (let i = rest.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [rest[i], rest[j]] = [rest[j], rest[i]];
    }
    this.songs.splice(this.index + 1, rest.length, ...rest);
    return rest.length;
  }

  clear() {
    this.songs = [];
    this.index = -1;
    this.ended = false;
  }
}
