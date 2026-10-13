import assert from 'node:assert/strict';
import { test } from 'node:test';
import { time } from '../src/commands.js';
import { pickBest } from '../src/match.js';
import { classifyInput, matchSong, songsFor } from '../src/sources.js';
import { parseEmbed, parseSpotifyLink } from '../src/spotify.js';
import { explainYtDlpError, toVideo } from '../src/ytdlp.js';

const video = (title, durationSec, channel = 'Someone') => ({ id: title, title, durationSec, channel, url: `u:${title}` });

test('recognises links and searches', () => {
  assert.deepEqual(classifyInput('https://open.spotify.com/intl-de/playlist/37i9dQZF1DX?si=abc'), { type: 'spotify', kind: 'playlist', id: '37i9dQZF1DX' });
  assert.deepEqual(classifyInput('https://youtu.be/dQw4w9WgXcQ?t=3'), { type: 'youtube-video', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' });
  assert.deepEqual(classifyInput('https://music.youtube.com/watch?v=abc&list=RDabc'), { type: 'youtube-video', url: 'https://www.youtube.com/watch?v=abc' });
  assert.deepEqual(classifyInput('youtube.com/playlist?list=PL123'), { type: 'youtube-playlist', url: 'https://www.youtube.com/playlist?list=PL123' });
  assert.deepEqual(classifyInput('  daft punk get lucky '), { type: 'search', query: 'daft punk get lucky' });
  assert.equal(parseSpotifyLink('https://example.com/track/1'), null);
});

test('skips live and cover versions unless asked for', () => {
  const results = [video('Song (Live at Wembley)', 300), video('Song (Cover)', 200), video('Song (Official Audio)', 200)];
  assert.equal(pickBest(results, { query: 'song' }).title, 'Song (Official Audio)');
  assert.equal(pickBest(results, { query: 'song live' }).title, 'Song (Live at Wembley)');
});

test('prefers the recording with the right length', () => {
  const results = [video('Song (Official Video)', 420), video('Song', 201, 'Artist - Topic')];
  assert.equal(pickBest(results, { query: 'artist - song', durationSec: 200 }).title, 'Song');
});

test('reads Spotify playlists and tracks from the embed page', () => {
  const page = (entity) => `<script id="__NEXT_DATA__" type="application/json">${JSON.stringify({ props: { pageProps: { state: { data: { entity } } } } })}</script>`;
  const list = parseEmbed(page({
    name: 'Mix',
    trackList: [
      { title: 'One', subtitle: 'A', duration: 200400 },
      { title: 'Gone', subtitle: 'B', duration: 1000, isPlayable: false },
    ],
  }), 'playlist');
  assert.deepEqual(list, { title: 'Mix', tracks: [{ title: 'One', artist: 'A', durationSec: 200 }] });

  const track = parseEmbed(page({ name: 'Solo', artists: [{ name: 'X' }, { name: 'Y' }], duration: 180000 }), 'track');
  assert.deepEqual(track.tracks, [{ title: 'Solo', artist: 'X, Y', durationSec: 180 }]);

  assert.throws(() => parseEmbed('<html></html>', 'playlist'), /private/);
});

test('Spotify songs are matched only when asked to', async () => {
  const searches = [];
  const ytdlp = { search: async (q) => { searches.push(q); return [video('One (Official Audio)', 200)]; } };
  const html = `<script id="__NEXT_DATA__" type="application/json">${JSON.stringify({ props: { pageProps: { state: { data: { entity: { name: 'Mix', trackList: [{ title: 'One', subtitle: 'A', duration: 200000 }] } } } } } })}</script>`;
  const fetchImpl = async () => ({ ok: true, text: async () => html });

  const found = await songsFor('https://open.spotify.com/playlist/abc', { ytdlp, requestedBy: 'u1', fetchImpl });
  assert.equal(found.isList, true);
  assert.equal(found.songs[0].url, null);
  assert.equal(searches.length, 0);

  await matchSong(found.songs[0], ytdlp);
  assert.deepEqual(searches, ['A - One']);
  assert.equal(found.songs[0].url, 'u:One (Official Audio)');
});

test('yt-dlp entries and errors', () => {
  assert.equal(toVideo({ id: 'x', title: '[Deleted video]' }), null);
  assert.equal(toVideo({ id: 'x', title: 'T', channel: 'C', duration: 61.6 }).durationSec, 62);
  assert.match(explainYtDlpError('ERROR: [youtube] x: Sign in to confirm you’re not a bot'), /cookies/);
  assert.equal(explainYtDlpError('WARNING: a\nERROR: something broke\n'), 'something broke');
});

test('times read like a music player', () => {
  assert.equal(time(65), '1:05');
  assert.equal(time(3723), '1:02:03');
  assert.equal(time(null), '?:??');
});
