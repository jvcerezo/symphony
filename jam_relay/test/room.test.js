import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { CODE_PATTERN } from '../src/index.js';
import { JamRoom, MAX_GUESTS } from '../src/room.js';

// Stand-ins for the Workers runtime: sockets, socket pairs, the Durable
// Object's hibernation API, and a Response that allows status 101.
class FakeSocket {
  constructor() {
    this.readyState = 1;
    this.sent = [];
    this.closed = null;
    this.attachment = null;
  }
  send(data) {
    if (this.readyState !== 1) throw new Error('closed');
    this.sent.push(data);
  }
  close(code, reason) {
    this.readyState = 3;
    this.closed ??= { code, reason };
  }
  serializeAttachment(value) {
    this.attachment = structuredClone(value);
  }
  deserializeAttachment() {
    return this.attachment;
  }
  json() {
    return this.sent.map((s) => JSON.parse(s));
  }
}

globalThis.WebSocketPair = class {
  constructor() {
    this[0] = new FakeSocket();
    this[1] = new FakeSocket();
  }
};

globalThis.Response = class {
  constructor(body, init = {}) {
    this.body = body;
    this.status = init.status ?? 200;
    this.webSocket = init.webSocket;
  }
};

class FakeCtx {
  constructor() {
    this.sockets = [];
  }
  acceptWebSocket(ws, tags) {
    this.sockets.push({ ws, tags });
  }
  getWebSockets(tag) {
    return this.sockets.filter((s) => s.tags.includes(tag)).map((s) => s.ws);
  }
}

let ctx;
let room;

beforeEach(() => {
  ctx = new FakeCtx();
  room = new JamRoom(ctx, {});
});

const upgrade = (role) =>
  room.fetch({ url: `https://relay.test/rooms/ABC234/${role}`, headers: new Map([['Upgrade', 'websocket']]) });
const check = () => room.fetch({ url: 'https://relay.test/rooms/ABC234', headers: new Map() });
const serverSide = () => ctx.sockets.at(-1).ws;

async function openHost() {
  const res = await upgrade('host');
  assert.equal(res.status, 101);
  return serverSide();
}

async function openGuest() {
  const res = await upgrade('guest');
  assert.equal(res.status, 101);
  const ws = serverSide();
  return { ws, id: ws.deserializeAttachment().id };
}

test('a code is open only while its host is connected', async () => {
  assert.equal((await check()).status, 404);
  const host = await openHost();
  assert.equal((await check()).status, 200);
  room.webSocketClose(host, 1000, '');
  assert.equal((await check()).status, 404);
});

test('a second host cannot take a running code', async () => {
  await openHost();
  assert.equal((await upgrade('host')).status, 409);
});

test('guests need a running Jam', async () => {
  assert.equal((await upgrade('guest')).status, 404);
});

test('frames flow both ways, addressed per guest', async () => {
  const host = await openHost();
  const a = await openGuest();
  const b = await openGuest();
  assert.deepEqual(host.json(), [
    { e: 'open', id: a.id },
    { e: 'open', id: b.id },
  ]);

  room.webSocketMessage(a.ws, '{"type":"hello"}');
  assert.deepEqual(host.json().at(-1), { e: 'msg', id: a.id, d: '{"type":"hello"}' });

  room.webSocketMessage(host, JSON.stringify({ to: b.id, d: 'state' }));
  assert.deepEqual(b.ws.sent, ['state']);
  assert.deepEqual(a.ws.sent, []);
});

test('the host can remove a guest, and guests leaving are announced', async () => {
  const host = await openHost();
  const a = await openGuest();
  const b = await openGuest();

  room.webSocketMessage(host, JSON.stringify({ to: a.id, close: true }));
  assert.equal(a.ws.closed.code, 1000);

  room.webSocketClose(b.ws, 1000, 'bye');
  assert.deepEqual(host.json().at(-1), { e: 'close', id: b.id });
});

test('when the host leaves, every guest is disconnected', async () => {
  const host = await openHost();
  const a = await openGuest();
  const b = await openGuest();
  room.webSocketClose(host, 1006, '');
  assert.equal(a.ws.closed.code, 1001);
  assert.equal(b.ws.closed.code, 1001);
});

test('junk, oversized and binary frames are dropped', async () => {
  const host = await openHost();
  const a = await openGuest();
  const before = host.sent.length;
  room.webSocketMessage(a.ws, 'x'.repeat(64 * 1024 + 1));
  room.webSocketMessage(a.ws, new ArrayBuffer(4));
  room.webSocketMessage(host, 'not json');
  room.webSocketMessage(host, JSON.stringify({ to: 'nobody', d: 'x' }));
  assert.equal(host.sent.length, before);
  assert.deepEqual(a.ws.sent, []);
});

test(`a Jam holds at most ${MAX_GUESTS} guests`, async () => {
  await openHost();
  for (let i = 0; i < MAX_GUESTS; i++) await openGuest();
  assert.equal((await upgrade('guest')).status, 429);
});

test('only 6-character codes without look-alikes are routed', () => {
  assert.match('/rooms/ABC234/host', CODE_PATTERN);
  assert.match('/rooms/XYZ789', CODE_PATTERN);
  for (const bad of ['/rooms/abc234/host', '/rooms/ABC10O', '/rooms/ABCD/host', '/rooms/ABC234/admin', '/rooms/ABCI23']) {
    assert.doesNotMatch(bad, CODE_PATTERN);
  }
});
