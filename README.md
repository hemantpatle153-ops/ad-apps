# Ad-funded app family

Free Android apps that earn from AdMob, sharing one Flutter core.

```
packages/app_core   ads (banner, interstitial, rewarded), EU consent, theme, links
apps/qr_scanner     app 1: QR and barcode scanner, QR maker, scan history
apps/daily_sudoku   app 2: daily puzzle with streak, 4 levels, notes, hints (rewarded ad for extra)
apps/doc_scanner    app 3: camera document scanner (auto edges, crop, filters) to multi-page PDF
apps/expense_tracker app 4: daily expenses, monthly budget, category insights, CSV export
apps/water_habit    app 5: water goal and daily habits with streaks and local reminders
apps/snakes_ladders app 6: Dice Dhamaal, two games in one: Ludo (vs computer, pass & play, online rooms with voice chat) and Snakes & Ladders
apps/multi_speaker  app 7: one song on many speakers in sync (phones on the same Wi-Fi/hotspot, each on its own speaker)
apps/video_player   app 8: video player: folders, gestures, subtitles, background audio, PiP, private folder
```

Package names are `in.onlysoftware.<folder name>`. Every app works offline; the only network use is ads (Multi Speaker also talks to other phones on the local Wi-Fi).
The release commands below work the same in every app folder (replace `qr_scanner` with the app).

## Run on your phone

Needs Flutter (stable) and Android Studio with an Android SDK.

```
cd apps/qr_scanner
flutter pub get
flutter run            # phone connected with USB debugging on
flutter test
```

Debug builds show Google's **test ads**. Tapping them is safe. Never tap real ads in your own app.

## Release build (Google Play)

Play bundles are built on the laptop with one script. It needs two things that never go in git, in `Downloads\APPS\signing`:

- `<app>-upload.jks` and `<app>.key.properties` (storePassword, keyAlias, keyPassword): the upload key of each app. Back these up; a lost upload key needs a reset request to Google. If one is missing, the script prints the `keytool` command to create it.
- `admob.json`: the real AdMob IDs (copy `tool/admob.example.json`). Only Daily Sudoku needs a rewarded ID.

```
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1               # all 8 apps
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 qr_scanner    # one app
```

Bundles land in `Downloads\APPS\play_release`. A bundle build (`bundleRelease`) refuses to run without the upload key, `-PadmobAppId` and the ad unit `--dart-define`s, so a Play upload can never carry debug keys or Google's test ads. APK builds (`flutter build apk`, CI) still fall back to debug keys and test ads.

Before each new upload, raise `version:` in the app's `pubspec.yaml` (the number after `+` must go up every time).

## Before publishing

- Privacy policies: `website/build.py` writes one page per app into `website/public/privacy/`; the apps link to `https://dice-dhamaal.web.app/privacy/<app>.html` (Firebase Hosting, free). Publish after any change with `python website/build.py` then `firebase deploy --only hosting` from `website/`.
- Store listing text, Data safety answers, permission declarations and content rating notes for each app: `docs/play/`.
- Store graphics: `apps/<app>/store/play_icon_512.png` and `feature_graphic.png` (`python tool/generate_icons.py --only feature`). Screenshots: take 2 to 8 on a phone.
- `tool/check_16kb.sh <apk>` checks Play's 16 KB page size rule; CI runs it on every test APK.
- Package names can't change after the first upload. Dice Dhamaal ships as `in.onlysoftware.dice_dhamaal` (folder `apps/snakes_ladders`, once its PR is merged).
- Target audience: 13 and older.

## Ad rules this code follows

- Dice Dhamaal asks for the microphone only when a player joins an online voice room, and only then.
- Interstitials only at natural breaks, at most once every 2 minutes (`AdConfig.interstitialCooldown`): leaving a scan result (QR), finishing a puzzle (Sudoku), saving a PDF (Doc Scanner), every third saved expense (Expense Tracker), reaching the water goal or adding a habit (Water), finishing a game (Dice Dhamaal).
- Rewarded ads only when the user asks for something extra: a 4th+ Sudoku hint or a second chance after 3 mistakes.
- One adaptive banner above the bottom navigation, never overlapping buttons.
- No ads on app open. Google's consent form shows to EU/UK users before any ad request, with "Ad privacy choices" in Settings.
