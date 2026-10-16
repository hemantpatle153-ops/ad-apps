// Room logic shared with the app (apps/video_player/lib/src/party):
// codes, the timeline state and the follower that keeps a player on it.
// Kept free of browser and Firebase calls so it runs under `node --test`.

/** Letters and digits that can't be mixed up when read out (no 0/O, 1/I/L). */
export const roomCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function newRoomCode(random = Math.random) {
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += roomCodeAlphabet[Math.floor(random() * roomCodeAlphabet.length)];
  }
  return code;
}

/** Upper case, no spaces or dashes. Null if it can't be a room code. */
export function normalizeRoomCode(raw) {
  const code = String(raw ?? '').toUpperCase().replace(/[\s-]/g, '');
  if (code.length !== 6) return null;
  for (const c of code) if (!roomCodeAlphabet.includes(c)) return null;
  return code;
}

/** A room code from a page address like .../#K7QF2M or ...?code=K7QF2M. */
export function codeFromLocation(hash, search) {
  const fromHash = normalizeRoomCode(String(hash ?? '').replace(/^#/, ''));
  if (fromHash) return fromHash;
  const params = new URLSearchParams(search ?? '');
  return normalizeRoomCode(params.get('code') ?? params.get('c'));
}

/** Room state, as the app writes it under watch/<code>/state. Times in µs. */
export function parseState(v) {
  return {
    playing: v?.playing === true,
    pos: Number(v?.pos) || 0,
    at: Number(v?.at) || 0,
    rate: Number(v?.rate) || 1,
  };
}

export function positionAt(s, nowUs) {
  return s.playing ? s.pos + Math.round((nowUs - s.at) * s.rate) : s.pos;
}

export const isHls = (url) => /\.m3u8(\?|#|$)/i.test(url ?? '');

/** Same check as the app: unknown target length, or within 3 s. */
export function sameLength(ms, targetMs) {
  return !(targetMs > 0) || Math.abs(ms - targetMs) <= 3000;
}

/**
 * Keeps a <video>-like player on the room's timeline: small drift is fixed
 * by playing a little faster or slower, big gaps by seeking. A port of the
 * app's TimelineFollower with the online settings.
 */
export class TimelineFollower {
  constructor({ nowUs, steadyNowUs = nowUs, nudgeAboveUs = 250000 }) {
    this.nowUs = nowUs;
    this.steadyNowUs = steadyNowUs;
    this.nudgeAboveUs = nudgeAboveUs;
    this.settleUntilUs = 0;
    this.rateNudged = false;
  }

  /** A new state arrived: correct right away. */
  reset() {
    this.settleUntilUs = 0;
  }

  /** [p]: { currentTime (s), duration (s), paused, buffering, playbackRate, play(), pause() }. */
  follow(p, s) {
    const target = positionAt(s, this.nowUs());
    const durUs = Number.isFinite(p.duration) ? p.duration * 1e6 : 0;
    if (durUs > 0 && target > durUs) return;
    if (s.playing === p.paused) s.playing ? p.play() : p.pause();
    const err = p.currentTime * 1e6 - target;
    if (!s.playing) {
      if (Math.abs(err) > 300000) p.currentTime = target / 1e6;
      this.resetRate(p, s);
      return;
    }
    if (p.buffering || this.steadyNowUs() < this.settleUntilUs) return;
    if (Math.abs(err) > 1500000) {
      // Aim a little ahead: the seek itself takes time.
      p.currentTime = (target + 400000) / 1e6;
      this.settleUntilUs = this.steadyNowUs() + 1500000;
      this.resetRate(p, s);
    } else if (Math.abs(err) > this.nudgeAboveUs) {
      const nudge = Math.max(-0.08, Math.min(0.08, err / 4000000));
      p.playbackRate = s.rate * (1 - nudge);
      this.rateNudged = true;
    } else {
      this.resetRate(p, s);
    }
  }

  resetRate(p, s) {
    if (this.rateNudged || p.playbackRate !== s.rate) {
      p.playbackRate = s.rate;
      this.rateNudged = false;
    }
  }
}

export const partyEmojis = ['😂', '😍', '😮', '😢', '👏', '🔥', '❤️', '👍'];

export function clip(text, max) {
  const t = String(text ?? '').trim();
  return t.length > max ? t.slice(0, max) : t;
}
