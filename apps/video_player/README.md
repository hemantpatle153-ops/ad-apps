# Video Player

Free, ad-funded Android video player in Flutter. Finds every video on the
phone, plays almost any format (libmpv through `media_kit`), and works offline.

## Features

- Videos grouped by folder with thumbnails, length, size and quality; sort by
  name, date, size or length; search across all videos; "NEW" badges
- Plays mp4, mkv, avi, webm, 3gp, mov, flv, ts and more, plus http(s)/HLS links
- Gestures: left side brightness, right side volume, swipe to seek,
  double tap to skip 10 s (fast keyframe jumps over a 30 s read-ahead
  cache; middle toggles play), press and hold for 2x speed, pinch to zoom
- Screen lock, fit / stretch / crop / 16:9 / 4:3, rotation lock, speed 0.25x to 4x
- Subtitles: embedded tracks, a matching .srt next to the video (Android 10 and
  older; Android 11+ only lets apps read media files, so pick the file there),
  pick a file, text size, colour and background box. Find captions online
  (OpenSubtitles: by the exact file first, then by name, in chosen
  languages), remembered per video. Sync by tapping "Next line now" /
  "Last line now" when a line is spoken, or with the delay buttons
- Audio track choice, play audio in the background with notification controls
- Picture-in-picture (button, or automatically when leaving the app)
- Resume where you stopped, "Continue watching" card, recently played list
- "Open with Video Player" from file managers and other apps
- Private folder locked with a PIN (videos are moved into app storage and
  removed from the gallery; moving them back restores the original folder)
- Dark and light themes, list or grid view, hide folders, share a video
- Player tools: 10-band equalizer with presets and night mode, volume boost
  to 200%, audio and subtitle delay, subtitle position, brightness / contrast /
  saturation / gamma / hue, rotate and mirror, sleep timer, A-B repeat, repeat
  one / all, shuffle, playing queue, frame-by-frame step, screenshots (saved to
  Pictures/Video Player), bookmarks, chapters, hardware / software decoder

## Watch together

One phone opens a video and taps More, then Watch with friends, and picks:

- **Online, with a code**: anywhere in the world. Firebase Realtime Database
  (project `dice-dhamaal`, shared with the Ludo game, data under `watch/`)
  carries only play, pause, seek, speed, chat and emoji. The video itself is
  never uploaded: a link opens on every phone, and a phone video must already
  be on each friend's phone (they pick their copy; the app ranks the one with
  the same length first). Everyone follows a shared timeline on Firebase's
  server clock. Rules to add in the Firebase console:
  `/mnt/project-files/video_player/firebase_watch_rules.md` (project files).
- **Nearby, on the same Wi-Fi or hotspot**: no internet or server. Friends
  stream the video from the host phone (HTTP with range requests) and join by
  QR code, the nearby list or the address. Clock sync over Wi-Fi, a seek when
  more than 1.5 s off, small speed nudges below that.

Both have chat and emoji reactions over the video. Live-streaming a phone
file to friends over the internet is not built: it would use the host's
upload data and, on many mobile networks, a paid TURN relay.

## Caption search key

Caption search uses OpenSubtitles.com. Each person pastes their own free API
key (Settings > Caption search key, or straight from the search sheet), so
downloads count against their own free quota. A build may also carry a
fallback key with `--dart-define=OPENSUBTITLES_API_KEY=...` (CI reads the
optional repository secret of that name); no key is ever committed.

## Ads

`packages/app_core` handles AdMob and the EU
consent form. One adaptive banner on the folder, video list and search screens
only, never on the player or the private folder. An interstitial may show when
a video is closed, at most once every 2 minutes. Debug and current builds use
Google's test ad IDs.

## Permissions

`READ_MEDIA_VIDEO` on Android 13+, `READ_EXTERNAL_STORAGE` up to Android 12,
`WRITE_EXTERNAL_STORAGE` only up to Android 10 (private folder), plus
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` for background audio, `CAMERA` (optional) to
scan a watch party QR code, Wi-Fi state and multicast to find parties nearby. No
`MANAGE_EXTERNAL_STORAGE`. Play Console will ask for the photo and video
permissions declaration: the app's core purpose is playing the user's videos.

## Build

```
flutter pub get
flutter test
flutter run                      # phone with USB debugging
```

Release (needs `android/key.properties`, never committed):

```
flutter build appbundle --release \
  -PadmobAppId=ca-app-pub-XXXX~YYYY \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/1111 \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXX/2222
flutter build apk --release      # same flags
```

`tool/gen_icon.py` (run from this folder) draws the launcher and
notification icons; `tool/icon_512.png` is the Play Store icon.
The `apk` job in CI builds a test APK on GitHub (debug-signed,
test ads) and saves it on branch apk-video_player.
