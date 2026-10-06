# Google Play release checklist (all 8 apps)

Developer name on Play: **Only Software**. Every app: free, has ads (AdMob + Google consent form), no login, made for ages 13+.

Each app has its own sheet with the store text, Data safety answers, permission declarations, content rating hints and policy risks:

| # | App (store name) | Package | Sheet | Privacy policy URL |
|---|---|---|---|---|
| 1 | QR & Barcode Scanner | `in.onlysoftware.qr_scanner` | [qr_scanner.md](qr_scanner.md) | https://dice-dhamaal.web.app/privacy/qr_scanner.html |
| 2 | Daily Sudoku | `in.onlysoftware.daily_sudoku` | [daily_sudoku.md](daily_sudoku.md) | https://dice-dhamaal.web.app/privacy/daily_sudoku.html |
| 3 | Doc Scanner: PDF & OCR | `in.onlysoftware.doc_scanner` | [doc_scanner.md](doc_scanner.md) | https://dice-dhamaal.web.app/privacy/doc_scanner.html |
| 4 | Expense Tracker: Daily Budget | `in.onlysoftware.expense_tracker` | [expense_tracker.md](expense_tracker.md) | https://dice-dhamaal.web.app/privacy/expense_tracker.html |
| 5 | Water Reminder & Habit Tracker | `in.onlysoftware.water_habit` | [water_habit.md](water_habit.md) | https://dice-dhamaal.web.app/privacy/water_habit.html |
| 6 | Multi Speaker: Sync Music | `in.onlysoftware.multi_speaker` | [multi_speaker.md](multi_speaker.md) | https://dice-dhamaal.web.app/privacy/multi_speaker.html |
| 7 | Video Player: Watch Together | `in.onlysoftware.video_player` | [video_player.md](video_player.md) | https://dice-dhamaal.web.app/privacy/video_player.html |
| 8 | Dice Dhamaal: Ludo & Snakes | `in.onlysoftware.dice_dhamaal` (folder `apps/snakes_ladders`, branch `ludo-game`) | [snakes_ladders.md](snakes_ladders.md) | https://dice-dhamaal.web.app/privacy/dice_dhamaal.html |

The privacy pages come from `website/build.py`. Deploy them (`firebase deploy --only hosting`) and open each link in a browser **before** you fill the Play forms. Play rejects an app whose policy link does not open.

---

## 1. One time: the developer account

- [ ] Create the account at https://play.google.com/console (one-time fee, 25 USD). Choose **Personal** account if you have no company papers. (An **Organization** account needs a D-U-N-S number but skips the testing rule below.)
- [ ] Finish identity verification (ID card, address) and phone/email verification. The legal name stays private for a personal account; the public **developer name** can be "Only Software".
- [ ] Set a public **contact email** (Play shows it on every app page; the privacy policies tell users to write there). Set the **website** to `https://dice-dhamaal.web.app` (needed for app-ads.txt, see step 6).

## 2. Testing rule for new personal accounts (very important)

Personal accounts made after 13 November 2023 cannot publish to Production at once:

- [ ] Upload the first build to **Testing > Closed testing**.
- [ ] Add **at least 12 testers** (an email list or a Google Group). Send them the opt-in link. They must **opt in and stay opted in for 14 days in a row**. Ask them to install the app and really use it; Google checks that.
- [ ] After 14 days, the Dashboard shows **Apply for production**. Answer the short questions (who tested, what you changed after feedback).
- [ ] This is per app. Tip: use one Google Group with 15+ friends for all 8 apps and start all 8 closed tests on the same day.

## 3. Create each app

- [ ] **Create app**: name (from the sheet), default language English, **App** or **Game** (Daily Sudoku and Dice Dhamaal are Games; the rest are Apps), **Free**, accept the declarations.
- [ ] **App signing by Google Play**: keep it ON (it is the default for .aab uploads). Google keeps the real signing key; you keep only the **upload key** (`upload-keystore.jks` + `key.properties`). Back up the upload key and its passwords in two safe places. If you lose it, you can ask Google to reset it, but it takes days.
- [ ] Package name is fixed forever after the first upload. Check `applicationId` in `android/app/build.gradle.kts` first. For Dice Dhamaal, build from branch `ludo-game` (package `in.onlysoftware.dice_dhamaal`), **not** from `main` (old offline game, package `in.onlysoftware.snakes_ladders`).
- [ ] Build with real AdMob IDs (see the main README "Release build"). Debug/test ad IDs must never reach Production.
- [ ] **Target API level**: Play only accepts new apps that target the current required Android version (each August it moves up one; check the warning on the App bundle page). Update Flutter if the bundle is refused.

## 4. App content (Policy > App content) - same steps for every app

Fill these for each app with the answers in its sheet:

- [ ] Privacy policy (URL from the table above)
- [ ] Ads: **Yes, my app contains ads**
- [ ] App access: **All functionality is available without special access** (no login). For apps with online rooms, add a note how to test (in the sheet).
- [ ] Content rating (IARC questionnaire) - hints in each sheet
- [ ] Target audience and content: **13-15, 16-17, 18 and over**. Do not tick any under-13 group.
- [ ] Data safety - table in each sheet
- [ ] **Advertising ID**: **Yes**, the app uses the advertising ID (the AdMob SDK adds the `AD_ID` permission). Purposes: Advertising or marketing, Analytics, Fraud prevention/security.
- [ ] Government apps: **No**. News app: **No**.
- [ ] Financial features: **My app doesn't provide any financial features** (all 8 apps; see Expense Tracker sheet for why).
- [ ] Health apps: **No health features**, except Water Reminder (see its sheet).
- [ ] Foreground service and Photo & video permission declarations appear only for Multi Speaker and Video Player (Play asks automatically when it sees the permission in the bundle).

## 5. Store listing graphics

| Item | Size and format | Ready file |
|---|---|---|
| App icon | 512 x 512 px, 32-bit PNG (alpha ok), max 1 MB | `apps/<folder>/store/play_icon_512.png` |
| Feature graphic | 1024 x 500 px, JPG or 24-bit PNG (**no transparency**) | `apps/<folder>/store/feature_graphic.png` |
| Phone screenshots | **2 to 8**. JPG or 24-bit PNG. Each side 320-3840 px, long side max 2x short side. Use 1080 x 1920 (portrait). Give at least 4 for better placement. | take on a real phone |
| Tablet screenshots | optional (7" and 10") | - |
| Promo video | optional, a YouTube link | - |

Screenshot rules: show the real app only. No other company's logo or app (no YouTube, Netflix, WhatsApp, JBL, Samsung logos), no "No.1 / best" text, no fake ratings. Hide your own personal data (names, files, expenses) in screenshots.

## 6. AdMob side (once per app)

- [ ] In AdMob, add the app, create the ad units (banner + interstitial; Daily Sudoku also rewarded). After the app is live on Play, **link** the AdMob app to the Play listing.
- [ ] **Privacy & messaging > GDPR**: create and **publish** one European consent message for these apps. Without a published message the in-app consent form never shows and EU/UK ad revenue is limited.
- [ ] **app-ads.txt**: put `website/public/app-ads.txt` with the line AdMob gives you (`google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0`) and deploy, so it is at `https://dice-dhamaal.web.app/app-ads.txt`. The website in Play Console must be this same domain.
- [ ] Never click your own live ads. Add your phones as **test devices** in AdMob.

## 7. Firebase (Video Player and Dice Dhamaal only)

- [ ] Deploy the database rules from `firebase/database.rules.json` (branch `ludo-game`) before release: `firebase deploy --only database`. They contain both `rooms` (Dice Dhamaal) and `watch` (Video Player).
- [ ] In Firebase, register both Android packages in project `dice-dhamaal` (already done for the app IDs in code; check in Project settings).

## 8. Before you press "Send for review"

- [ ] Open **Pre-launch report** in the closed test and fix crashes.
- [ ] Check **App bundle explorer > Permissions** for each bundle. Every permission listed there must be explained in the sheet. Remove any that the app does not need (see the risks in each sheet).
- [ ] Check that the in-app name, launcher name and store name match closely.
- [ ] First review of a new app can take up to 7 days (sometimes more). Answer any Play email quickly.
