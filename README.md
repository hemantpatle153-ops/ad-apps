# Ad-funded app family

Free Android apps that earn from AdMob, sharing one Flutter core.

```
packages/app_core   ads (banner, interstitial, rewarded), EU consent, theme, links
apps/qr_scanner     app 1: QR and barcode scanner, QR maker, scan history
apps/daily_sudoku   app 2: daily puzzle with streak, 4 levels, notes, hints (rewarded ad for extra)
apps/doc_scanner    app 3: camera document scanner (auto edges, crop, filters) to multi-page PDF
apps/expense_tracker app 4: daily expenses, monthly budget, category insights, CSV export
apps/water_habit    app 5: water goal and daily habits with streaks and local reminders
apps/snakes_ladders app 6: Snakes & Ladders game, vs computer or 2-4 player pass-and-play, themes, sounds
```

Package names are `in.onlysoftware.<folder name>`. Every app works offline; the only network use is ads.
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

## Release build

1. Create an upload keystore once and keep it safe (losing it means you can't update the app):
   `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `apps/qr_scanner/android/key.properties` (git-ignored):
   ```
   storeFile=/home/you/upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
3. In AdMob, add the app and create a banner, an interstitial and a rewarded ad unit. Then build:
   ```
   flutter build appbundle \
     -PadmobAppId=ca-app-pub-XXXX~YYYY \
     --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXX/1111 \
     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXX/2222 \
     --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXX/3333
   ```
4. Upload `build/app/outputs/bundle/release/app-release.aab` to a closed test track in Play Console.

## Before publishing

- The package name is `in.onlysoftware.qr_scanner` (`android/app/build.gradle.kts` and `lib/src/app.dart`). Change it now if you want a different one; it can't change after the first upload.
- Put your hosted privacy policy URL in `lib/src/app.dart`.
- Replace the launcher icon (e.g. with the `flutter_launcher_icons` package).
- Play Console Data safety: declare "Device or other IDs" collected for advertising (AdMob). Scan history, documents, expenses and habits stay on the device.
- Target audience: 13 and older.

## Ad rules this code follows

- Interstitials only at natural breaks, at most once every 2 minutes (`AdConfig.interstitialCooldown`): leaving a scan result (QR), finishing a puzzle (Sudoku), saving a PDF (Doc Scanner), every third saved expense (Expense Tracker), reaching the water goal or adding a habit (Water), finishing a game (Snakes & Ladders).
- Rewarded ads only when the user asks for something extra: a 4th+ Sudoku hint or a second chance after 3 mistakes.
- One adaptive banner above the bottom navigation, never overlapping buttons.
- No ads on app open. Google's consent form shows to EU/UK users before any ad request, with "Ad privacy choices" in Settings.
