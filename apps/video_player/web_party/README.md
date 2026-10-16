# Watch Together on the web

A single static page that joins or starts the same online rooms as the
Video Player app (Firebase Realtime Database, `watch/<code>`, project
`dice-dhamaal`). No build step: plain HTML, CSS and JavaScript modules.

- **Join**: open `<page>/#K7QF2M` (or type the code). A link party plays the
  link; a file party asks the viewer to pick their own copy, like the app.
- **Start**: paste a video link (mp4, webm, m3u8) or a Google Drive share
  link, or pick a file on this device. Friends join from the app or the page.
  Closing the tab ends the room.
- **Google Drive**: the host uploads the video to Drive and shares it as
  "Anyone with the link". The room stores the file's direct stream address
  (`drive.usercontent.google.com/download?id=…&confirm=t`), so friends stream
  it from Drive without having a copy, in the app or the browser. Drive limits
  how often one file can be downloaded per day, and may block sharing of files
  it flags for copyright.
- Play, pause, seek and speed stay in sync both ways with the app (same
  timeline maths as `lib/src/party/follower.dart`), plus chat, emoji
  reactions, mute and report (`reports/`, same as the app).
- The video itself never goes through the room's server.

Browsers play MP4 (H.264/AAC) and WebM everywhere. MKV, HEVC and AVI files
often don't play in a browser; the page says so.

## Test

```
node --test        # room codes, state and the sync follower (sync.js)
```

## Host on InfinityFree (free)

1. Sign up at https://www.infinityfree.com and create a hosting account
   with a free subdomain (for example `luzzanwatch.infinityfreeapp.com`).
2. Control panel → **Online File Manager** → open `htdocs`, delete any
   placeholder page there, and upload every file in this folder except
   `test/`, `package.json` and `README.md`:
   `index.html`, `party.js`, `sync.js`, `config.js`, `style.css`, `icon.png`.
3. Open `https://<your subdomain>/`. If https doesn't load yet, request the
   free SSL certificate in the client area (SSL Certificates) and wait for it.
4. Put the address in the app: set the default of `webPartyUrl` in
   `lib/src/party/online.dart` to `https://<your subdomain>/` (with the
   final `/`), or build with `--dart-define=WEB_PARTY_URL=...`. The room
   panel and the invite then show `https://<your subdomain>/#CODE`.

Nothing in Firebase needs changing: anonymous sign-in and the `watch/`
rules already allow the page. Any other static host works the same way.
