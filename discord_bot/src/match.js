// Versions people rarely mean unless they ask for them.
const UNWANTED = [
  'live', 'cover', 'remix', 'karaoke', 'instrumental', 'sped up', 'slowed',
  'nightcore', '8d', 'reverb', 'acoustic', 'reaction', 'tutorial', 'lesson',
];
const PREFERRED = ['official audio', 'audio', 'lyrics', 'official video'];

/**
 * Picks the search result most likely to be the song asked for. When the
 * length of the real song is known (a Spotify track), results far off it are
 * other recordings or long videos.
 */
export function pickBest(videos, { query, durationSec = null } = {}) {
  const wanted = (query ?? '').toLowerCase();
  let best = null;
  let bestScore = -Infinity;
  videos.forEach((video, rank) => {
    const title = video.title.toLowerCase();
    let score = -rank * 2;
    for (const word of UNWANTED) {
      const asked = hasWord(wanted, word);
      const has = hasWord(title, word);
      if (has && !asked) score -= 30;
      // "song live" wants the live one over the studio recording.
      else if (asked) score += has ? 15 : -15;
    }
    const preferred = PREFERRED.findIndex((p) => title.includes(p));
    if (preferred >= 0) score += 8 - preferred * 2;
    // "Artist - Topic" channels carry the album recording.
    if (/ - topic$/i.test(video.channel)) score += 6;
    if (durationSec && video.durationSec) {
      const off = Math.abs(video.durationSec - durationSec);
      score -= off <= 5 ? 0 : off <= 15 ? 5 : off <= 40 ? 20 : 60;
    }
    if (score > bestScore) {
      best = video;
      bestScore = score;
    }
  });
  return best;
}

function hasWord(text, word) {
  return new RegExp(`(^|[^a-z0-9])${word}([^a-z0-9]|$)`).test(text);
}
