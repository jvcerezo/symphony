import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GuildPlayer } from '../src/player.js';

const settle = () => new Promise((r) => setTimeout(r, 20));

function playerWith(ytdlp) {
  const player = new GuildPlayer({ guild: { id: 'g1' }, ytdlp });
  // Stands in for a voice connection; nothing here touches it.
  player.connection = { joinConfig: { channelId: 'c1' }, state: { status: 'destroyed' }, destroy() {} };
  const events = [];
  for (const name of ['start', 'failed', 'finished', 'gaveUp', 'left']) {
    player.on(name, (...args) => events.push([name, args[0]?.title ?? args[0]]));
  }
  return { player, events };
}

test('a song with no match is skipped and the next one tried', async () => {
  const { player, events } = playerWith({
    search: async (q) => { throw new Error(`no match for ${q}`); },
  });
  player.add([{ title: 'A' }, { title: 'B' }]);
  await settle();
  assert.deepEqual(events.map((e) => e[0]), ['failed', 'failed', 'finished']);
  player.leave(null);
});

test('stops after three songs in a row fail', async () => {
  const { player, events } = playerWith({ search: async () => [] });
  player.add([1, 2, 3, 4, 5].map((n) => ({ title: `S${n}` })));
  await settle();
  assert.deepEqual(events.map((e) => e[0]), ['failed', 'failed', 'failed', 'gaveUp']);
  assert.equal(player.queue.isEmpty, true);
  player.leave(null);
});

test('leaving clears the queue and says why', async () => {
  const { player, events } = playerWith({ search: async () => [] });
  player.leave('Everyone left.');
  assert.deepEqual(events, [['left', 'Everyone left.']]);
  assert.equal(player.channelId, null);
});
