// Watch Together on the web: joins or starts the same rooms as the Video
// Player app (Firebase Realtime Database, path watch/<code>).
import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js';
import { getAuth, signInAnonymously } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js';
import {
  getDatabase, ref, child, get, set, update, push, remove, onValue, onChildAdded,
  onDisconnect, query, limitToLast, serverTimestamp,
} from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js';
import { firebaseConfig, playStoreUrl } from './config.js';
import {
  TimelineFollower, clip, codeFromLocation, isHls, newRoomCode, normalizeRoomCode,
  parseState, partyEmojis, positionAt, sameLength,
} from './sync.js';

const $ = (id) => document.getElementById(id);
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getDatabase(app);

let uid = null;
let serverOffsetMs = 0;
const serverNowUs = () => (Date.now() + serverOffsetMs) * 1000;
const steadyNowUs = () => performance.now() * 1000;

// ---- Small helpers --------------------------------------------------------

function toast(text, ms = 3500) {
  const t = $('toast');
  t.textContent = text;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.hidden = true; }, ms);
}

function show(screen) {
  for (const id of ['home', 'pick', 'room']) $(id).hidden = id !== screen;
}

function formatTime(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) seconds = 0;
  const s = Math.floor(seconds % 60);
  const m = Math.floor(seconds / 60) % 60;
  const h = Math.floor(seconds / 3600);
  const mm = h ? String(m).padStart(2, '0') : String(m);
  return `${h ? `${h}:` : ''}${mm}:${String(s).padStart(2, '0')}`;
}

const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private window */ } },
};

async function askName() {
  const dialog = $('name-dialog');
  $('name-input').value = store.get('partyName') ?? '';
  dialog.showModal();
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => {
      const name = clip($('name-input').value, 30);
      if (dialog.returnValue !== 'ok' || !name) return resolve(null);
      store.set('partyName', name);
      resolve(name);
    }, { once: true });
  });
}

async function connect() {
  if (!uid) {
    const cred = await signInAnonymously(auth);
    uid = cred.user.uid;
  }
  // .info values live in the browser, so read them with a listener.
  await new Promise((resolve) => {
    const off = onValue(ref(db, '.info/serverTimeOffset'), (snap) => {
      serverOffsetMs = Number(snap.val()) || 0;
      resolve();
    });
    room.subs.push(off);
  });
}

function explain(e) {
  const code = e?.code ?? '';
  if (code.includes('network') || code === 'unavailable') {
    return "Couldn't reach the internet. Check your connection and try again.";
  }
  if (code.includes('permission')) return `The watch party server said no. (${code})`;
  return `Something went wrong. Try again. (${code || e?.message || 'error'})`;
}

// ---- Room ----------------------------------------------------------------

const room = {
  code: null,
  host: false,
  name: '',
  video: null, // { title, url, dur }
  state: parseState(null),
  members: [],
  muted: new Set(),
  subs: [],
  joinedAtMs: 0,
  ended: false,
};

const video = $('video');
let buffering = false;
let hls = null;
const follower = new TimelineFollower({ nowUs: serverNowUs, steadyNowUs });
const player = {
  get currentTime() { return video.currentTime; },
  set currentTime(v) { video.currentTime = v; },
  get duration() { return video.duration; },
  get paused() { return video.paused; },
  get buffering() { return buffering; },
  get playbackRate() { return video.playbackRate; },
  set playbackRate(v) { video.playbackRate = v; },
  play() {
    video.play().then(() => { $('tap-start').hidden = true; }).catch(() => {
      // The browser wants a tap before sound plays.
      $('tap-start').hidden = false;
    });
  },
  pause() { video.pause(); },
};

function loadSource({ url, file }) {
  if (hls) { hls.destroy(); hls = null; }
  if (file) {
    video.src = URL.createObjectURL(file);
  } else if (isHls(url) && !video.canPlayType('application/vnd.apple.mpegurl') && window.Hls?.isSupported()) {
    hls = new window.Hls();
    hls.loadSource(url);
    hls.attachMedia(video);
  } else {
    video.src = url;
  }
}

video.addEventListener('waiting', () => { buffering = true; });
video.addEventListener('playing', () => { buffering = false; });
video.addEventListener('canplay', () => { buffering = false; });
video.addEventListener('error', () => {
  toast(room.video?.url
    ? "This browser can't play that link."
    : "This browser can't play that file. MP4 (H.264) works everywhere.", 6000);
});

let syncTimer = null;
function syncNow() {
  if (!room.code || room.ended) return;
  follower.follow(player, room.state);
  renderTime();
}

async function writeState(next) {
  room.state = next;
  follower.reset();
  syncNow();
  try {
    await set(ref(db, `watch/${room.code}/state`), {
      playing: next.playing, pos: Math.round(next.pos), at: Math.round(next.at), rate: next.rate, by: uid,
    });
  } catch {
    // Offline for a moment; Firebase sends it when the connection returns.
  }
}

const here = () => Math.round(video.currentTime * 1e6);

function requestPlay() {
  writeState({ playing: true, pos: here(), at: serverNowUs(), rate: room.state.rate });
}
function requestPause() {
  const now = serverNowUs();
  writeState({ playing: false, pos: positionAt(room.state, now), at: now, rate: room.state.rate });
}
function requestSeek(toSeconds) {
  const max = Number.isFinite(video.duration) ? video.duration : Infinity;
  const pos = Math.max(0, Math.min(max, toSeconds)) * 1e6;
  writeState({ playing: room.state.playing, pos, at: serverNowUs(), rate: room.state.rate });
}

function listen() {
  const base = `watch/${room.code}`;
  room.joinedAtMs = serverNowUs() / 1000;
  const me = ref(db, `${base}/members/${uid}`);
  onDisconnect(me).remove();
  room.subs.push(
    onValue(ref(db, `${base}/state`), (snap) => {
      if (!snap.exists()) return;
      room.state = parseState(snap.val());
      follower.reset();
      syncNow();
    }),
    onValue(ref(db, `${base}/members`), (snap) => {
      room.members = Object.values(snap.val() ?? {}).map((m) => String(m?.name ?? 'Friend'));
      renderMembers();
    }),
    onValue(ref(db, `${base}/host`), (snap) => {
      if (!snap.exists() && !room.ended) end('Your friend ended the watch party');
    }),
    onChildAdded(query(ref(db, `${base}/chat`), limitToLast(30)), (snap) => {
      const v = snap.val() ?? {};
      const m = { from: String(v.from ?? 'Friend'), text: String(v.text ?? ''), emoji: v.e === true };
      if (room.muted.has(m.from) && m.from !== room.name) return;
      const at = Number(v.at) || 0;
      const old = at !== 0 && at < room.joinedAtMs - 2000;
      if (m.emoji) {
        if (!old) floatEmoji(m.text);
      } else {
        addChatLine(m);
      }
    }),
  );
  syncTimer = setInterval(syncNow, 500);
}

function end(reason) {
  room.ended = true;
  clearInterval(syncTimer);
  video.pause();
  $('ended').textContent = reason;
  $('ended').hidden = false;
}

async function leave() {
  clearInterval(syncTimer);
  for (const off of room.subs.splice(0)) { try { off(); } catch { /* already off */ } }
  if (room.code && uid) {
    try {
      if (room.host) {
        await remove(ref(db, `watch/${room.code}`));
      } else {
        await onDisconnect(ref(db, `watch/${room.code}/members/${uid}`)).cancel();
        await remove(ref(db, `watch/${room.code}/members/${uid}`));
      }
    } catch { /* offline; Firebase removes it when it notices */ }
  }
  video.removeAttribute('src');
  video.load();
  Object.assign(room, { code: null, host: false, video: null, ended: false, members: [] });
  $('chat').textContent = '';
  $('ended').hidden = true;
  history.replaceState(null, '', location.pathname);
  show('home');
}

// ---- Join / start -----------------------------------------------------------

async function join(code) {
  const name = await askName();
  if (!name) return;
  try {
    await connect();
    const snap = await get(ref(db, `watch/${code}`));
    const v = snap.val();
    if (!v || !v.host || typeof v.video !== 'object') {
      toast('No watch party with that code. Check the code and that your friend still has the video open.', 6000);
      return;
    }
    Object.assign(room, {
      code, name, host: v.host === uid, video: {
        title: String(v.video.title ?? 'Video'), url: v.video.url ?? null, dur: Number(v.video.dur) || 0,
      },
    });
    await set(ref(db, `watch/${code}/members/${uid}`), { name });
  } catch (e) {
    toast(explain(e), 6000);
    return;
  }
  history.replaceState(null, '', `#${code}`);
  if (room.video.url) {
    enterRoom({ url: room.video.url });
  } else {
    $('pick-title').textContent = room.video.title;
    $('pick-length').textContent = room.video.dur ? ` (${formatTime(room.video.dur / 1000)})` : '';
    $('pick-warning').hidden = true;
    show('pick');
  }
}

$('pick-file').addEventListener('change', () => {
  const file = $('pick-file').files[0];
  if (!file) return;
  // Check the length before entering, like the app's picker does.
  const probe = document.createElement('video');
  probe.preload = 'metadata';
  probe.src = URL.createObjectURL(file);
  probe.onloadedmetadata = () => {
    const ms = probe.duration * 1000;
    URL.revokeObjectURL(probe.src);
    if (!sameLength(ms, room.video.dur)) {
      $('pick-warning').textContent =
        `This video is ${formatTime(ms / 1000)} long, your friend's is ${formatTime(room.video.dur / 1000)}. ` +
        'It may be a different copy. Playing it anyway.';
      $('pick-warning').hidden = false;
    }
    enterRoom({ file });
  };
  probe.onerror = () => enterRoom({ file });
});
$('pick-cancel').addEventListener('click', leave);

async function start({ url, file }) {
  const name = await askName();
  if (!name) return;
  let title = 'Video';
  let dur = 0;
  if (file) {
    title = file.name.replace(/\.[^.]+$/, '') || 'Video';
    dur = await new Promise((resolve) => {
      const probe = document.createElement('video');
      probe.preload = 'metadata';
      probe.src = URL.createObjectURL(file);
      probe.onloadedmetadata = () => resolve(Math.round(probe.duration * 1000) || 0);
      probe.onerror = () => resolve(0);
    });
  } else {
    try {
      const last = decodeURIComponent(new URL(url).pathname.split('/').pop() ?? '');
      title = last.replace(/\.[^.]+$/, '') || new URL(url).hostname;
    } catch { title = 'Video link'; }
  }
  try {
    await connect();
    let code = null;
    for (let i = 0; i < 5 && !code; i++) {
      const c = newRoomCode();
      if (!(await get(ref(db, `watch/${c}/host`))).exists()) code = c;
    }
    if (!code) throw new Error('no-free-code');
    // One multi-path update, so each child's security rule applies.
    await update(ref(db, `watch/${code}`), {
      host: uid,
      created: serverTimestamp(),
      video: { title: clip(title, 120), url: url ?? null, dur },
      state: { playing: false, pos: 0, at: serverNowUs(), rate: 1, by: uid },
      [`members/${uid}`]: { name },
    });
    // Closing the tab ends the room, like the app host leaving.
    onDisconnect(ref(db, `watch/${code}`)).remove();
    Object.assign(room, { code, name, host: true, video: { title, url: url ?? null, dur } });
  } catch (e) {
    toast(explain(e), 6000);
    return;
  }
  history.replaceState(null, '', `#${room.code}`);
  enterRoom({ url, file });
}

function enterRoom(source) {
  $('room-code').textContent = room.code;
  $('room-title').textContent = room.video.title;
  $('chat').textContent = '';
  $('ended').hidden = true;
  room.ended = false;
  show('room');
  loadSource(source);
  listen();
}

$('join-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const code = normalizeRoomCode($('join-code').value);
  if (!code) return toast('Party codes have 6 letters and numbers, like K7QF2M');
  join(code);
});

$('host-file').addEventListener('change', () => {
  const f = $('host-file').files[0];
  $('host-file-name').textContent = f ? f.name : '';
  if (f) $('host-url').value = '';
});

$('host-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const file = $('host-file').files[0];
  const url = $('host-url').value.trim();
  if (file) return start({ file });
  if (!/^https?:\/\//i.test(url)) return toast('Paste a video link (https://…) or choose a file.');
  if (location.protocol === 'https:' && /^http:\/\//i.test(url)) {
    return toast('This page is secure (https), so browsers block http:// video links. Use an https link.', 6000);
  }
  start({ url });
});

// ---- Controls ---------------------------------------------------------------

$('btn-play').addEventListener('click', () => (room.state.playing ? requestPause() : requestPlay()));
$('btn-back').addEventListener('click', () => requestSeek(video.currentTime - 10));
$('btn-fwd').addEventListener('click', () => requestSeek(video.currentTime + 10));
$('tap-start').addEventListener('click', () => { $('tap-start').hidden = true; syncNow(); video.play().catch(() => {}); });
$('btn-mute').addEventListener('click', () => {
  video.muted = !video.muted;
  $('btn-mute').textContent = video.muted ? '🔇' : '🔊';
});
$('btn-full').addEventListener('click', () => {
  if (document.fullscreenElement) document.exitFullscreen();
  else $('stage').requestFullscreen?.().catch(() => {});
});
let seeking = false;
$('seek').addEventListener('input', () => { seeking = true; });
$('seek').addEventListener('change', () => {
  seeking = false;
  if (Number.isFinite(video.duration)) requestSeek(($('seek').value / 1000) * video.duration);
});
document.addEventListener('keydown', (e) => {
  if ($('room').hidden || e.target.tagName === 'INPUT') return;
  if (e.key === ' ') { e.preventDefault(); $('btn-play').click(); }
  if (e.key === 'ArrowLeft') $('btn-back').click();
  if (e.key === 'ArrowRight') $('btn-fwd').click();
  if (e.key === 'f') $('btn-full').click();
});
$('btn-leave').addEventListener('click', leave);
$('btn-share').addEventListener('click', async () => {
  const link = `${location.origin}${location.pathname}#${room.code}`;
  const text = `Watch "${room.video.title}" with me: open ${link} or enter code ${room.code} in Video Player's Watch together.`;
  try {
    if (navigator.share) await navigator.share({ text });
    else { await navigator.clipboard.writeText(text); toast('Invite copied'); }
  } catch { /* cancelled */ }
});
window.addEventListener('beforeunload', () => {
  if (room.host && room.code) remove(ref(db, `watch/${room.code}`));
});

function renderTime() {
  $('btn-play').textContent = room.state.playing ? '❚❚' : '▶';
  $('time').textContent = `${formatTime(video.currentTime)} / ${formatTime(video.duration)}`;
  if (!seeking && Number.isFinite(video.duration) && video.duration > 0) {
    $('seek').value = String(Math.round((video.currentTime / video.duration) * 1000));
  }
}

// ---- Chat, reactions, mute and report ---------------------------------------

function post(text, emoji = false) {
  push(ref(db, `watch/${room.code}/chat`), {
    uid, from: room.name, text, e: emoji, at: serverTimestamp(),
  }).catch(() => {});
}

$('chat-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const text = clip($('chat-input').value, 300);
  if (!text) return;
  post(text);
  $('chat-input').value = '';
});

for (const emoji of partyEmojis) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = emoji;
  b.addEventListener('click', () => post(emoji, true));
  $('emoji-row').append(b);
}

function floatEmoji(emoji) {
  const s = document.createElement('span');
  s.textContent = emoji;
  s.style.left = `${Math.random() * 30}px`;
  $('floats').append(s);
  setTimeout(() => s.remove(), 2700);
}

function nameButton(name) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = name;
  if (name !== room.name) b.addEventListener('click', () => personActions(name));
  return b;
}

function addChatLine(m) {
  const li = document.createElement('li');
  li.dataset.from = m.from;
  li.append(nameButton(m.from), document.createTextNode(m.text));
  $('chat').append(li);
  li.scrollIntoView({ block: 'nearest' });
}

function renderMembers() {
  const box = $('members');
  box.textContent = '';
  const label = document.createElement('span');
  label.className = 'muted small';
  label.textContent = `${room.members.length} watching:`;
  box.append(label, ...room.members.map(nameButton));
}

async function personActions(name) {
  const dialog = $('person-dialog');
  $('person-name').textContent = name;
  $('person-mute').textContent = room.muted.has(name) ? 'Unmute' : 'Mute this person';
  dialog.showModal();
  dialog.addEventListener('close', async () => {
    if (dialog.returnValue === 'mute') {
      if (room.muted.has(name)) {
        room.muted.delete(name);
        toast(`${name} unmuted`);
      } else {
        mute(name);
        toast(`${name} muted on this device`);
      }
    } else if (dialog.returnValue === 'report') {
      const lines = [...$('chat').children].filter((li) => li.dataset.from === name);
      const said = lines.length ? lines[lines.length - 1].textContent.slice(name.length) : '';
      try {
        await push(ref(db, 'reports'), {
          code: room.code,
          seat: 0,
          name: clip(name, 40),
          reason: clip(`video_player_web: ${said}`, 200),
          by: uid,
          at: serverTimestamp(),
        });
        toast('Thanks. We will review this report.');
      } catch {
        toast("Couldn't send the report. Try again.");
      }
      mute(name);
    }
  }, { once: true });
}

function mute(name) {
  room.muted.add(name);
  for (const li of [...$('chat').children]) if (li.dataset.from === name) li.remove();
}

// ---- Boot -------------------------------------------------------------------

$('get-app').href = playStoreUrl;
const linked = codeFromLocation(location.hash, location.search);
if (linked) {
  $('join-code').value = linked;
  join(linked);
}
