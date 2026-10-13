import assert from 'node:assert/strict';
import { test } from 'node:test';
import { SongQueue } from '../src/queue.js';

const song = (n) => ({ title: `Song ${n}` });
const titles = (songs) => songs.map((s) => s.title);

test('plays songs in order and runs out', () => {
  const q = new SongQueue();
  q.add([song(1), song(2)]);
  assert.equal(q.advance().title, 'Song 1');
  assert.equal(q.advance().title, 'Song 2');
  assert.equal(q.advance(), null);
  assert.equal(q.current, null);
});

test('a song added after the queue ran out plays next', () => {
  const q = new SongQueue();
  q.add([song(1)]);
  q.advance();
  q.advance();
  q.add([song(2)]);
  assert.equal(q.advance().title, 'Song 2');
});

test('playnext goes straight after the current song', () => {
  const q = new SongQueue();
  q.add([song(1), song(2), song(3)]);
  q.advance();
  q.add([song('X')], { next: true });
  assert.deepEqual(titles(q.upcoming), ['Song X', 'Song 2', 'Song 3']);
});

test('repeat song plays it again unless skipped', () => {
  const q = new SongQueue();
  q.add([song(1), song(2)]);
  q.loop = 'song';
  q.advance();
  assert.equal(q.advance().title, 'Song 1');
  assert.equal(q.advance({ skipped: true }).title, 'Song 2');
});

test('repeat queue starts over after the last song', () => {
  const q = new SongQueue();
  q.add([song(1), song(2)]);
  q.loop = 'queue';
  q.advance();
  q.advance();
  assert.equal(q.advance().title, 'Song 1');
});

test('remove counts from the next song', () => {
  const q = new SongQueue();
  q.add([song(1), song(2), song(3)]);
  q.advance();
  assert.equal(q.remove(2).title, 'Song 3');
  assert.equal(q.remove(5), null);
  assert.equal(q.remove(0), null);
  assert.deepEqual(titles(q.upcoming), ['Song 2']);
});

test('shuffle leaves the playing song where it is', () => {
  const q = new SongQueue();
  q.add([1, 2, 3, 4, 5].map(song));
  q.advance();
  q.shuffle(() => 0);
  assert.equal(q.current.title, 'Song 1');
  assert.deepEqual(titles(q.upcoming).sort(), ['Song 2', 'Song 3', 'Song 4', 'Song 5']);
});

test('stops taking songs at the length limit', () => {
  const q = new SongQueue({ maxLength: 3 });
  assert.equal(q.add([1, 2, 3, 4, 5].map(song)), 3);
  assert.equal(q.add([song(6)]), 0);
});
