# Video Player

Free, ad-funded Android video player in Flutter. Finds every video on the
phone, plays almost any format (libmpv through `media_kit`), and works offline.

## Features

- Videos grouped by folder with thumbnails, length, size and quality; sort by
  name, date, size or length; search across all videos; "NEW" badges
- Plays mp4, mkv, avi, webm, 3gp, mov, flv, ts and more, plus http(s)/HLS links
- Gestures: left side brightness, right side volume, swipe to seek,
  double tap to skip 10 s (middle toggles play), pinch to zoom, hold a
  finger on the video to play at 2x (twice the current speed if already
  faster) until it lifts
- Quick skips: 96 MB cache that reads 20 s ahead and keeps what was
  played, so 10-second skips usually come from memory; quick repeated taps
  add up (+10, +20, +30) instead of restarting from the old position
- Screen lock, fit / stretch / crop / 16:9 / 4:3, rotation lock, speed 0.25x to 4x
- Subtitles: embedded tracks, a matching .srt next to the video (Android 10 and
  older; Android 11+ only lets apps read media files, so pick the file there),
  pick a file, text size, colour and background box
- Subtitle sync: manual (-1 s, -0.1 s, +0.1 s, +1 s, reset) and Auto sync,
  which decodes three 4-minute stretches of the video's sound on the phone,
  finds where speech is, and picks the delay (up to 2 minutes either way) and
  frame-rate fix (23.976 / 24 / 25 fps) that best fit the subtitle lines.
  Works on subtitle files (picked or next to the video), not on
  tracks inside the video; it says so when it isn't sure instead of guessing
- Audio track choice, play audio in the background with notification controls
- Picture-in-picture (button, or automatically when leaving the app)
- Resume where you stopped, "Continue watching" card, recently played list
- "Open with Video Player" from file managers and other apps
- Private folder locked with a PIN (videos are moved into app storage and
  removed from the gallery; moving them back restores the original folder)
- Dark and light themes

## Ads

`packages/app_core` handles AdMob and the EU
consent form. One adaptive banner on the folder, video list and search screens
only, never on the player or the private folder. An interstitial may show when
a video is closed, at most once every 2 minutes. Debug and current builds use
Google's test ad IDs.

## Permissions

`READ_MEDIA_VIDEO` on Android 13+, `READ_EXTERNAL_STORAGE` up to Android 12,
`WRITE_EXTERNAL_STORAGE` only up to Android 10 (private folder), plus
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` for background audio. No
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
