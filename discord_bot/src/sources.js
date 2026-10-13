import { pickBest } from './match.js';
import { fetchSpotify, parseSpotifyLink } from './spotify.js';

const YOUTUBE = /^(https?:\/\/)?((www|m|music)\.)?(youtube\.com|youtu\.be)\//i;

/** What `/play` was given: a Spotify link, a YouTube link or words to search. */
export function classifyInput(text) {
  const input = text.trim();
  const spotify = parseSpotifyLink(input);
  if (spotify) return { type: 'spotify', ...spotify };
  if (YOUTUBE.test(input)) {
    const url = new URL(input.startsWith('http') ? input : `https://${input}`);
    // A /playlist link is the whole list. A watch link inside a list (often
    // an endless "Mix") plays just that video.
    if (url.pathname === '/playlist' && url.searchParams.get('list')) {
      return { type: 'youtube-playlist', url: `https://www.youtube.com/playlist?list=${url.searchParams.get('list')}` };
    }
    const id = url.hostname.endsWith('youtu.be') ? url.pathname.slice(1) : url.searchParams.get('v');
    if (id) return { type: 'youtube-video', url: `https://www.youtube.com/watch?v=${id}` };
  }
  return { type: 'search', query: input };
}

/**
 * Turns `/play` input into songs. Returns `{ title, songs, isList }`, where
 * `title` names the playlist or album when there is one. Spotify songs are
 * only matched to a YouTube video when they are about to play.
 */
export async function songsFor(text, { ytdlp, requestedBy, fetchImpl }) {
  const input = classifyInput(text);
  const by = { requestedBy };

  if (input.type === 'spotify') {
    const { title, tracks } = await fetchSpotify(input, fetchImpl);
    if (tracks.length === 0) throw new Error('That Spotify list has no playable songs.');
    return {
      title,
      isList: input.kind !== 'track',
      songs: tracks.map((t) => ({ ...t, url: null, ...by })),
    };
  }
  if (input.type === 'youtube-playlist') {
    const { title, videos } = await ytdlp.playlist(input.url);
    if (videos.length === 0) throw new Error('That YouTube playlist is empty or private.');
    return { title, isList: true, songs: videos.map((v) => fromVideo(v, by)) };
  }
  if (input.type === 'youtube-video') {
    const video = await ytdlp.video(input.url);
    return { title: video.title, isList: false, songs: [fromVideo(video, by)] };
  }
  const video = pickBest(await ytdlp.search(input.query), { query: input.query });
  if (!video) throw new Error(`Nothing found for "${input.query}".`);
  return { title: video.title, isList: false, songs: [fromVideo(video, by)] };
}

/** Finds the YouTube video for a song that does not have one yet. */
export async function matchSong(song, ytdlp) {
  if (song.url) return song;
  const query = song.artist ? `${song.artist} - ${song.title}` : song.title;
  const video = pickBest(await ytdlp.search(query), { query, durationSec: song.durationSec });
  if (!video) throw new Error(`No YouTube match for "${query}".`);
  song.url = video.url;
  song.durationSec ??= video.durationSec;
  return song;
}

function fromVideo(video, extra) {
  return {
    title: video.title,
    artist: video.channel.replace(/ - Topic$/i, ''),
    durationSec: video.durationSec,
    url: video.url,
    ...extra,
  };
}
