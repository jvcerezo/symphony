import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseCommand } from '../src/commands.js';

test('reads s! commands and their words', () => {
  assert.deepEqual(parseCommand('s!play daft punk  get lucky'), { name: 'play', args: 'daft punk get lucky' });
  assert.deepEqual(parseCommand('  S!Skip '), { name: 'skip', args: '' });
  assert.deepEqual(parseCommand('s! queue 2'), { name: 'queue', args: '2' });
});

test('short forms map to the full command', () => {
  assert.equal(parseCommand('s!p song').name, 'play');
  assert.equal(parseCommand('s!np').name, 'nowplaying');
  assert.equal(parseCommand('s!q').name, 'queue');
  assert.equal(parseCommand('s!leave').name, 'stop');
});

test('ignores everything else', () => {
  assert.equal(parseCommand('/play song'), null);
  assert.equal(parseCommand('hello s!play'), null);
  assert.equal(parseCommand('s!'), null);
  assert.equal(parseCommand(''), null);
});
