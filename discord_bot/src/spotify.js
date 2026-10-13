const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const LINK = /open\.spotify\.com\/(?:intl-[a-z-]+\/)?(playlist|album|track)\/([A-Za-z0-9]+)/i;

/** `{ kind, id }` for a Spotify playlist, album or track link, else null. */
export function parseSpotifyLink(text) {
  const m = LINK.exec(text);
  return m ? { kind: m[1].toLowerCase(), id: m[2] } : null;
}

/**
 * Reads a public Spotify playlist, album or track from its embed page, the
 * same way the Symphony app imports playlists. No Spotify account needed.
 * Returns `{ title, tracks: [{ title, artist, durationSec }] }`.
 */
export async function fetchSpotify({ kind, id }, fetchImpl = fetch) {
  const res = await fetchImpl(`https://open.spotify.com/embed/${kind}/${id}`, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
  });
  if (!res.ok) throw new Error(`Spotify did not open that ${kind} (status ${res.status}).`);
  return parseEmbed(await res.text(), kind);
}

export function parseEmbed(html, kind) {
  const m = html.match(/<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/);
  const entity = m ? JSON.parse(m[1])?.props?.pageProps?.state?.data?.entity : null;
  if (!entity) throw new Error(`That Spotify ${kind} is private or could not be read.`);

  if (kind === 'track') {
    return {
      title: entity.name ?? entity.title,
      tracks: [{
        title: entity.name ?? entity.title,
        artist: (entity.artists ?? []).map((a) => a.name).join(', '),
        durationSec: seconds(entity.duration),
      }],
    };
  }
  return {
    title: entity.name ?? entity.title ?? 'Spotify playlist',
    tracks: (entity.trackList ?? [])
      .filter((t) => t.title && t.isPlayable !== false)
      .map((t) => ({ title: t.title, artist: t.subtitle ?? '', durationSec: seconds(t.duration) })),
  };
}

function seconds(ms) {
  return Number.isFinite(ms) && ms > 0 ? Math.round(ms / 1000) : null;
}
