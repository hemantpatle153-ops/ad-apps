# Multi Speaker

Free Android app that plays one song on many speakers at the same moment.
Earns from AdMob ads (one banner, plus an interstitial when a party ends).

## What it does

Android sends Bluetooth music to only one speaker at a time, and no app can
change that. So Multi Speaker uses one phone per speaker:

1. Every phone joins the same Wi-Fi, or the host phone's hotspot.
2. The host phone picks songs. Other phones join by scanning its QR code
   (or picking it from "Parties nearby", or typing its address).
3. The host sends each song file to the other phones over the local network,
   then every phone plays it on a shared clock, each on its own speaker
   (built-in, wired or Bluetooth).

No internet and no server: everything stays on the local network.

The app also tells people when their phone can drive two Bluetooth speakers
by itself (Samsung Dual audio, LE Audio "Audio sharing" / Auracast).

## How sync works (lib/src/sync)

- `clock.dart`: guests ping the host and keep the fastest round trips to
  learn the host's clock (the NTP idea), usually to within a few ms on Wi-Fi.
- `protocol.dart`: the host sends a `PlayState`: song, playing or paused, and
  "position P at host time T". Starts are scheduled 0.7 s ahead so every phone
  has seeked and is ready.
- `sync_controller.dart`: starts the player on schedule, then every 250 ms
  compares its position with the timeline. Drift over 25 ms is fixed by
  playing 3% faster or slower until it's gone; over 150 ms it re-seeks.
- Speaker delay: a Bluetooth speaker plays ~150-300 ms after the phone sends
  the sound. Each phone keeps a delay for its speaker and Bluetooth (200 ms
  by default) and plays that far ahead. People fine-tune it by ear with the
  slider.

`lib/src/net`: `party_host.dart` (HTTP for song files + WebSocket control on
port 47800, UDP beacon on 47801), `party_guest.dart` (download, clock pings,
reconnects after Wi-Fi blips), `discovery.dart`.

`test/party_test.dart` runs a real host and two guests over localhost with
pretend players and checks they stay within 15 ms.

## Run

```
flutter pub get
flutter test
flutter run            # phone connected with USB debugging on
```

Debug builds show Google's **test ads**. Never tap real ads in your own app.

## Release build

1. Create `android/key.properties` (git-ignored) pointing at the upload keystore:
   ```
   storeFile=C:/Users/you/Downloads/APPS/signing/multi_speaker-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
2. With real AdMob IDs (banner + interstitial; rewarded is unused):
   ```
   flutter build appbundle \
     -PadmobAppId=ca-app-pub-XXXX~YYYY \
     --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/1111 \
     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXX/2222
   ```

## Before publishing

- Put your hosted privacy policy URL in `lib/src/app.dart`.
- Play Console: the app uses a foreground "media playback" service (music
  keeps playing with the screen off) and the camera (only to scan the join
  code). Data safety: "Device or other IDs" for ads; songs never leave the
  local network.

The icon comes from `tool/gen_icon.py` (Pillow).
