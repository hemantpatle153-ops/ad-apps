import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TimelineFollower, clip, codeFromLocation, isHls, newRoomCode, normalizeRoomCode,
  parseState, positionAt, roomCodeAlphabet, sameLength,
} from '../sync.js';

test('room codes match the app', () => {
  assert.equal(roomCodeAlphabet, 'ABCDEFGHJKMNPQRSTUVWXYZ23456789');
  const code = newRoomCode();
  assert.equal(code.length, 6);
  assert.equal(normalizeRoomCode(code), code);
  assert.equal(normalizeRoomCode(' k7q-f2m '), 'K7QF2M');
  assert.equal(normalizeRoomCode('K7QF2'), null);
  assert.equal(normalizeRoomCode('K7QF2O'), null); // O is not used
  assert.equal(normalizeRoomCode(null), null);
});

test('a code comes from the page address', () => {
  assert.equal(codeFromLocation('#k7qf2m', ''), 'K7QF2M');
  assert.equal(codeFromLocation('', '?code=K7QF2M'), 'K7QF2M');
  assert.equal(codeFromLocation('', '?c=k7qf2m'), 'K7QF2M');
  assert.equal(codeFromLocation('#nope', ''), null);
});

test('state reads the app format and moves with the clock', () => {
  const s = parseState({ playing: true, pos: 10_000_000, at: 1_000_000, rate: 2, by: 'x' });
  assert.deepEqual(s, { playing: true, pos: 10_000_000, at: 1_000_000, rate: 2 });
  assert.equal(positionAt(s, 2_000_000), 12_000_000);
  assert.equal(positionAt({ ...s, playing: false }, 9e9), 10_000_000);
  assert.deepEqual(parseState(null), { playing: false, pos: 0, at: 0, rate: 1 });
});

test('helpers', () => {
  assert.ok(isHls('https://x/a.m3u8'));
  assert.ok(isHls('https://x/a.M3U8?token=1'));
  assert.ok(!isHls('https://x/a.mp4'));
  assert.ok(sameLength(60_000, 0));
  assert.ok(sameLength(60_000, 62_500));
  assert.ok(!sameLength(60_000, 64_000));
  assert.equal(clip('  hi  ', 30), 'hi');
  assert.equal(clip('x'.repeat(40), 30).length, 30);
});

function fakePlayer(over = {}) {
  return {
    currentTime: 0, duration: 100, paused: true, buffering: false, playbackRate: 1,
    plays: 0, pauses: 0,
    play() { this.paused = false; this.plays++; },
    pause() { this.paused = true; this.pauses++; },
    ...over,
  };
}

test('follower plays, pauses and seeks to the room', () => {
  let now = 50_000_000;
  const f = new TimelineFollower({ nowUs: () => now });
  const p = fakePlayer();
  f.follow(p, { playing: true, pos: 20_000_000, at: now, rate: 1 });
  assert.equal(p.plays, 1);
  assert.ok(Math.abs(p.currentTime - 20.4) < 1e-9, 'seeks a little ahead');
  // Paused room, player 1 s off: snaps to the spot.
  const q = fakePlayer({ paused: false, currentTime: 31 });
  f.follow(q, { playing: false, pos: 30_000_000, at: now, rate: 1 });
  assert.equal(q.pauses, 1);
  assert.equal(q.currentTime, 30);
});

test('follower nudges small drift and leaves tiny drift alone', () => {
  const now = 10_000_000;
  const f = new TimelineFollower({ nowUs: () => now });
  const s = { playing: true, pos: 5_000_000, at: now, rate: 1 };
  const p = fakePlayer({ paused: false, currentTime: 5.5 });
  f.follow(p, s);
  assert.ok(p.playbackRate < 1, 'ahead: slows down');
  p.currentTime = 5.1;
  f.follow(p, s);
  assert.equal(p.playbackRate, 1, 'close enough: normal speed');
  const r = fakePlayer({ paused: false, currentTime: 4.5 });
  f.follow(r, s);
  assert.ok(r.playbackRate > 1, 'behind: speeds up');
});

test('follower waits while buffering or settling, and past the end', () => {
  let steady = 0;
  const now = 10_000_000;
  const f = new TimelineFollower({ nowUs: () => now, steadyNowUs: () => steady });
  const s = { playing: true, pos: 50_000_000, at: now, rate: 1 };
  const p = fakePlayer({ paused: false, currentTime: 10, buffering: true });
  f.follow(p, s);
  assert.equal(p.currentTime, 10);
  p.buffering = false;
  f.follow(p, s);
  assert.ok(p.currentTime > 50);
  p.currentTime = 10;
  steady = 1_000_000; // still settling
  f.follow(p, s);
  assert.equal(p.currentTime, 10);
  const end = fakePlayer({ paused: false, currentTime: 10, duration: 40 });
  f.follow(end, s);
  assert.equal(end.currentTime, 10, 'room is past this copy\'s end');
});
