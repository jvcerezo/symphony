// One online Jam: the host's socket plus its guests' sockets.
//
// The relay never reads the Jam itself. A guest's frames go to the host
// wrapped as {e: 'msg', id, d}; the host addresses a guest with {to, d} or
// ends it with {to, close: true}. The host also hears {e: 'open', id} and
// {e: 'close', id} as guests come and go. When the host leaves, every guest
// is disconnected.
//
// Sockets are accepted with the hibernation API, so an idle Jam costs
// nothing; who each socket is lives in its attachment.

export const MAX_GUESTS = 16;
export const MAX_FRAME = 64 * 1024;

const OPEN = 1;

export class JamRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  /** The connected host's socket, if any. */
  host() {
    return this.ctx.getWebSockets('host').find((ws) => ws.readyState === OPEN);
  }

  guests() {
    return this.ctx.getWebSockets('guest').filter((ws) => ws.readyState === OPEN);
  }

  guest(id) {
    return this.ctx.getWebSockets(`g:${id}`).find((ws) => ws.readyState === OPEN);
  }

  async fetch(request) {
    const role = new URL(request.url).pathname.split('/')[3];
    if (request.headers.get('Upgrade') !== 'websocket') {
      // A plain GET asks whether a Jam with this code is running.
      return this.host() ? new Response('open') : new Response('no jam', { status: 404 });
    }
    if (role === 'host') {
      if (this.host()) return new Response('code taken', { status: 409 });
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server, ['host']);
      server.serializeAttachment({ role: 'host' });
      return new Response(null, { status: 101, webSocket: client });
    }
    if (role === 'guest') {
      const host = this.host();
      if (!host) return new Response('no jam', { status: 404 });
      if (this.guests().length >= MAX_GUESTS) return new Response('jam full', { status: 429 });
      const id = crypto.randomUUID().slice(0, 8);
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server, ['guest', `g:${id}`]);
      server.serializeAttachment({ role: 'guest', id });
      send(host, JSON.stringify({ e: 'open', id }));
      return new Response(null, { status: 101, webSocket: client });
    }
    return new Response('not found', { status: 404 });
  }

  webSocketMessage(ws, message) {
    if (typeof message !== 'string' || message.length > MAX_FRAME) return;
    const who = ws.deserializeAttachment();
    if (who?.role === 'guest') {
      const host = this.host();
      if (host) send(host, JSON.stringify({ e: 'msg', id: who.id, d: message }));
      return;
    }
    if (who?.role !== 'host') return;
    let envelope;
    try {
      envelope = JSON.parse(message);
    } catch {
      return;
    }
    if (typeof envelope?.to !== 'string') return;
    const target = this.guest(envelope.to);
    if (!target) return;
    if (envelope.close === true) {
      close(target, 1000, 'removed by host');
    } else if (typeof envelope.d === 'string') {
      send(target, envelope.d);
    }
  }

  webSocketClose(ws, code, reason) {
    this.left(ws);
    close(ws, code === 1005 ? 1000 : code, reason);
  }

  webSocketError(ws) {
    this.left(ws);
  }

  left(ws) {
    const who = ws.deserializeAttachment();
    if (who?.role === 'host') {
      for (const guest of this.guests()) close(guest, 1001, 'host left');
    } else if (who?.role === 'guest') {
      const host = this.host();
      if (host && host !== ws) send(host, JSON.stringify({ e: 'close', id: who.id }));
    }
  }
}

function send(ws, data) {
  try {
    ws.send(data);
  } catch {
    // Already closing; its close handler cleans up.
  }
}

function close(ws, code, reason) {
  try {
    ws.close(code, reason);
  } catch {
    // Already closed.
  }
}
