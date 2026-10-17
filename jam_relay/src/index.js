// Symphony Jam relay: passes Jam messages between a host and its guests
// when they are not on the same network. Only playback messages travel
// through it (which song, play/pause, position); never audio.
//
//   GET  /rooms/<CODE>          200 when a Jam with that code is running
//   WS   /rooms/<CODE>/host     the host's connection
//   WS   /rooms/<CODE>/guest    a guest's connection
//
// Each code is its own Durable Object (see room.js).

import { JamRoom } from './room.js';

export { JamRoom };

/** Online Jam codes: 6 characters, without look-alikes (0/O, 1/I/L). */
export const CODE_PATTERN = /^\/rooms\/([A-HJKMNP-Z2-9]{6})(?:\/(host|guest))?$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/') return new Response('Symphony Jam relay');
    const match = url.pathname.match(CODE_PATTERN);
    if (!match) return new Response('not found', { status: 404 });
    const room = env.ROOMS.get(env.ROOMS.idFromName(match[1]));
    return room.fetch(request);
  },
};
