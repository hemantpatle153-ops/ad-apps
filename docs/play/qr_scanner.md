# QR & Barcode Scanner - Play Console sheet

- Folder: `apps/qr_scanner` - Package: `in.onlysoftware.qr_scanner`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://docs.google.com/document/d/e/2PACX-1vQGUBqDjMOdmypiIrwgkwVXqCxpWgUuzt2sZvb6d8q1wgYsZyEMOV9MjD-9EARk3qEnIRMDwrn79iMi/pub

What the code really does: camera scan of QR codes and barcodes (flashlight, switch camera), result screen that knows links, UPI payment links, Wi-Fi codes, phone numbers, email and product numbers; copy and share; "Search product" opens a Google search in the browser; a QR maker for text/links/numbers; scan history (last 300) saved only on the phone, swipe to delete or clear all. No scanning from gallery images. Wi-Fi codes are only shown as text, the app does not join the network.

## 1. Store listing

**App name** (20/30)
```
QR & Barcode Scanner
```

**Short description** (76/80)
```
Scan QR codes and barcodes, open links, keep a history and make your own QR.
```

**Full description** (1194/4000)
```
Point your camera at a QR code or barcode and the result shows up at once. No sign-up, no setup.

WHAT IT READS
- Links: open them in your browser, copy or share them.
- UPI payment QR codes: tap "Pay with UPI app" to open your own UPI app. This app never handles money itself.
- Phone numbers and email addresses: call or write with one tap.
- Product barcodes: search the number on the web.
- Wi-Fi codes and plain text: see the full text and copy it.

SCAN COMFORTABLY
- Flashlight button for dark places.
- Switch between the front and back camera.
- The camera runs only while the Scan tab is open.

MAKE YOUR OWN QR CODE
Type any text, link or phone number and a QR code appears right away, ready for someone else to scan from your screen.

HISTORY ON YOUR PHONE
Your last 300 scans are kept on this phone so you can open them again. Swipe a scan away to delete it, or clear the whole history in Settings. The history is never uploaded.

PRIVACY
Codes are read on your phone. The app has no account and no cloud storage. It shows ads from Google AdMob; in the EU and UK you are asked for consent first and can change your choice later in Settings.

Light and dark theme follow your phone.
```

**Category:** Tools
**Tags (pick up to 5 in Play):** QR code scanner, Barcode scanner, Tools, Utilities, Productivity

## 2. Data safety

"Collected" in Play means the data leaves the phone. The scan history and created QR codes stay on the phone, so they are **not** collected.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob guesses a rough area from the IP address |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (ad views, taps) |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK; Google ML Kit (used by the scanner) sends usage/performance metrics |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID (AdMob); ML Kit install ID |
| Personal info, Financial info, Messages, Photos/videos, Audio, Files and docs, Calendar, Contacts, Health, Web browsing, Location (precise) | No | No | - | - | - | Camera frames are processed on the phone and never saved or sent |

Other answers:
- Is all user data encrypted in transit? **Yes** (AdMob and ML Kit use HTTPS).
- Do you provide a way for users to request deletion? **No** is allowed (no account). History: users delete it in the app. Ad data: Android Settings > Privacy > Ads.
- Does your app collect or share any of the required user data types? **Yes**.

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| CAMERA | "The camera is used only on the Scan screen to read QR codes and barcodes. Images are processed on the phone and are not saved or uploaded." | No form. Good to show a short in-app line before the first system prompt (see risks). |
| INTERNET | Ads only. | No |
| AD_ID (added by AdMob SDK) | Advertising ID declaration: **Yes**, for Advertising, Analytics, Fraud prevention. | Advertising ID form |

No foreground service, no storage, no location permission.

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other**.
- Violence, fear, sexuality, language, drugs, crude humor: **No**.
- Gambling or simulated gambling: **No**.
- Users can interact or exchange content with other users: **No** (sharing a result uses Android's share menu; there is no in-app chat).
- Shares the user's current location with others: **No**.
- Digital purchases: **No**.
- Unrestricted web browsing inside the app: **No** (links open in the user's own browser).
- Expected result: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** (one banner above the bottom bar; an interstitial at most once every 2 minutes, only when leaving a scan result).
- Target audience: **13-15, 16-17, 18+**. Appeals to children: **No**.
- Financial features: **None**. The "Pay with UPI app" button only opens the UPI link in the user's own payment app; this app does not move money, store payment data or connect to a bank.
- Health: none. Government: No. News: No.

## 6. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| Camera prompt at first launch with no explanation and no custom "permission denied" screen. The Scan tab is the first tab, so the system dialog is the first thing users see. | `apps/qr_scanner/lib/src/screens/scan_screen.dart:54`, `apps/qr_scanner/lib/src/screens/home_shell.dart:38` | Low risk (camera is the core feature). Better: add an `errorBuilder` to `MobileScanner` with a short "Allow camera to scan codes" message and a Settings button. |
| Privacy policy says the app can "connect to Wi-Fi from a scanned code", but the app only shows Wi-Fi codes as text (no join action). | `website/build.py:50`, `apps/qr_scanner/lib/src/scan_kind.dart:44-46` | Make the policy and listing match the app: remove "connect to Wi-Fi" from the policy (listing above already says "see the text"). |
| Store/launcher name mismatch: launcher says "QR Scanner", in-app title says "QR & Barcode Scanner". | `apps/qr_scanner/android/app/src/main/AndroidManifest.xml:6`, `apps/qr_scanner/lib/src/app.dart:17` | Not a violation, but keep the store name close to the launcher name. |
| Scanned links open without any safety check. | `apps/qr_scanner/lib/src/screens/result_screen.dart:42-43` | Not a Play rule. The user always taps "Open" first, which is fine. Don't claim "safe scanning" in the listing. |
