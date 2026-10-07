# Video Player - Play Console sheet

- Folder: `apps/video_player` - Package: `in.onlysoftware.video_player`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://docs.google.com/document/d/e/2PACX-1vTfrEbXLRvkphpIBmzE9dJ_gLWgh24QUcM0FZjossBmiuPtX29Vhs8ryciONNOotey4viCLpV3zf7Em/pub
- Uses Firebase project **dice-dhamaal** (Anonymous Auth + Realtime Database, path `watch/{code}`)

What the code really does: lists the phone's videos by folder (READ_MEDIA_VIDEO via photo_manager; supports "selected videos only" access), Recent tab, search, grid/list, hide folders; player (media_kit) with swipe gestures for brightness, volume and seeking, double-tap skip, speed, resume, audio track choice and audio delay, equalizer and night mode, picture options (e.g. mirror), subtitles (.srt/.ass/.vtt, delay, auto sync, style), sleep timer, bookmarks, chapters, play queue, background audio (foreground service) and picture-in-picture; "Play from a link" (http/https, HLS); "Open with" from file managers; share, properties, delete; **private folder** locked with a PIN (videos moved into app storage). **Watch together**: (1) *Nearby*: the host phone streams the video to friends on the same Wi-Fi (local HTTP, join by QR or nearby list); (2) *Online*: 6-letter room code via Firebase - only the video title or link, play/pause/seek state, member names, chat messages and emoji reactions go through Firebase; each friend plays their own copy of the file or the same link; rooms are deleted when the starter leaves or after 12 hours.

## 1. Store listing

**App name** (28/30)
```
Video Player: Watch Together
```

**Short description** (77/80)
```
Play videos with subtitles, gestures and PiP, and watch in sync with friends.
```

**Full description** (1658/4000)
```
A clean, fast video player for the videos on your phone, with a "Watch together" mode to enjoy a video in sync with friends.

YOUR LIBRARY
- Videos sorted by folder, plus a Recent list and search.
- Grid or list view. Hide folders you don't want to see.
- Open videos from your file manager or other apps with "Open with".

EASY CONTROLS
- Swipe for brightness, volume and seeking. Double-tap to skip.
- Playback speed, resume where you stopped, play queue.
- Picture-in-picture, and background audio when you leave the app.
- Sleep timer, bookmarks and chapters.

SOUND AND PICTURE
- Choose the audio track and fix audio delay.
- Equalizer and night mode for quieter loud scenes and clearer dialogue.
- Picture options such as mirror.
- Hardware decoding on or off.

SUBTITLES
Load .srt, .ass or .vtt files, change the delay, use auto sync, and add a dark box behind the text for easy reading.

PLAY FROM A LINK
Paste a video link (for example an .mp4 or .m3u8 address) to stream it.

PRIVATE FOLDER
Move personal videos into a PIN-locked folder inside the app. They leave your gallery until you move them back.

WATCH TOGETHER
- Nearby: on the same Wi-Fi, friends join by scanning your QR code and the video streams from your phone.
- Online: share a 6-letter code. Each friend plays their own copy of the video, or the same link, and play, pause and seek stay in sync. Send quick emoji reactions and short chat messages. Only the room details travel online, never your video file. Rooms are deleted automatically.

PRIVACY
No account needed. Your videos stay on your phone. The app shows ads from Google AdMob; EU and UK users are asked for consent first.
```

**Category:** Video Players & Editors
**Tags:** Video player, Media player, Subtitles, Watch party, Offline video

Listing rules for this app: never mention or show movie/TV brands, streaming sites, "free movies" or "download movies". Use your own videos in screenshots.

## 2. Data safety

Videos, private folder, playback positions, bookmarks and link history stay on the phone = not collected. The **Nearby** party streams the video directly from the host phone to friends' phones on the same local network (never to you or a third party) = recommended **not collected**. The **Online** room data goes through Firebase = **collected**.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source / note |
|---|---|---|---|---|---|---|
| Personal info > Name | Yes | No | No | Optional | App functionality | Name shown to friends in an online room (from Settings "My name in watch parties", or the phone's device name). Deleted with the room. |
| Personal info > User IDs | Yes | No | No | Optional | App functionality, Fraud prevention/security | Random Firebase anonymous ID, used by the database rules |
| Messages > Other in-app messages | Yes | No | No | Optional | App functionality | Chat (max 300 characters) and emoji reactions in online rooms; deleted with the room (max 12 h) |
| App activity > Other user-generated content | Yes | No | No | Optional | App functionality | Video title or the link being watched in an online room |
| App activity > Other actions | Yes | No | No | Optional | App functionality | Play / pause / seek / speed state of the room |
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK; ML Kit barcode scanning (QR join) metrics |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID; ML Kit install ID |
| Photos and videos > Videos | No | No | - | - | - | Files never uploaded; Nearby stream is local phone-to-phone |
| Web browsing history | No | No | - | - | - | Link history stays on the phone |

"Shared = No" for the room data because other room members get it only because the user chose to start/join the room (user-initiated), and Firebase is your service provider.

- Encrypted in transit: **Yes** (Firebase and AdMob use HTTPS).
- Deletion request: **Yes** - rooms delete themselves (starter leaves, or 12 hours); for anything else users can write to the contact email. No user account is created, so the Play "account deletion" URL is **not** required.

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| READ_MEDIA_VIDEO (Android 13+), READ_EXTERNAL_STORAGE (max SDK 32) | See declaration A. | **Photo and video permissions** declaration |
| WRITE_EXTERNAL_STORAGE (max SDK 29) + requestLegacyExternalStorage | Only Android 10 and older: move videos into and out of the private folder. | No |
| FOREGROUND_SERVICE_MEDIA_PLAYBACK (AudioService, type `mediaPlayback`) | See declaration B. | **Foreground service** declaration |
| CAMERA | "Used only to scan a watch party's QR code to join." | No |
| ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE, WAKE_LOCK, INTERNET | Find nearby parties on the same Wi-Fi, keep playback awake, online rooms, ads. | No |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

**Declaration A - Photo and video permissions (READ_MEDIA_VIDEO)**
> Video Player is a local video player. Its core function is to find all videos on the device, show them by folder, and play them, including folder browsing, search, "recent" and resume positions. Android's photo picker only returns single files chosen each time, so it cannot show the user's video library as folders or keep it updated when new videos are added. The app reads videos only (no photos), works only on the device and never uploads the files. Users can also grant access to selected videos only.

Choose the use case: **core functionality - media player / file manager style app that needs broad access to videos**.

**Declaration B - Foreground service: media playback**
> When the user turns on background audio (Settings > "When I leave the app during a video") or presses the home button while a video plays, the sound continues as audio-only playback with play/pause controls in the media notification, like a music player. The service runs only while media is playing and stops when the user pauses/stops or closes the player. Without it, playback would stop as soon as the screen is turned off.

Video to record (30-60 s): open a video > Settings shows the background option > go home > show the notification with controls and sound still playing > pause from the notification.

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other** (media player).
- App's own content: no violence, sexuality, language, drugs or gambling - answer **No**. (The user plays their own files; the app has no built-in content.)
- **Users can interact or exchange content: Yes** (online room chat, names, reactions).
- Shares user's location: **No**. Digital purchases: **No**.
- Unrestricted internet / web browsing: **No** (there is no browser; links play as video only). If the questionnaire asks whether users can access any online content, answer honestly that the user can play a video link they paste.
- Expected: Everyone / PEGI 3 / IARC 3+ with "Users Interact".

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner on the library, folder, search and join screens (never on the player); interstitial after closing the player (2-minute gap).
- Target audience: **13-15, 16-17, 18+**.
- Financial: none. Health: none. Government: No. News: No.
- App access: all functions work without login. Tell the reviewer: "Watch together > Online creates a 6-letter code on one phone; enter it on a second phone. No account needed."

## 6. Policy risks found in the code

| # | Risk | Where | What to do |
|---|---|---|---|
| 1 | **User-generated content (online chat + names) with no report, block or mute.** Play's UGC policy asks apps with user-to-user chat to let users report and block abusive users and to moderate. Rooms are private (code only), which lowers the risk, but reviewers may still flag it. | `apps/video_player/lib/src/party/party_widgets.dart:89-99` (chat list), `:100-114` (input), `apps/video_player/lib/src/party/online.dart:359-377` (send) | Add a long-press on a message/member: **Mute this person** (hide their messages on this phone) and **Report** (opens email to your contact address with room code + text). Add a one-line rule under the chat box: "Be kind. Abuse can be reported." |
| 2 | The **phone's device name is sent to Firebase by default** as the member name (often "Rahul's Galaxy"), without asking. The privacy policy says "the name you type". | `apps/video_player/lib/src/player/player_screen.dart:456-458`, `apps/video_player/lib/src/party/join_screen.dart:104-106`, `android/.../MainActivity.kt:54-57` | Ask for a name the first time the user starts or joins an online room (default empty, not the device name). |
| 3 | The permission screen says **"Nothing leaves your phone."** That is not true when the user starts an online room (title/link go to Firebase). | `apps/video_player/lib/src/screens/home_screen.dart:449-450` | Change to "Your videos never leave your phone." |
| 4 | Photo & video declaration: check the merged manifest. `photo_manager` may add READ_MEDIA_IMAGES / READ_MEDIA_AUDIO / ACCESS_MEDIA_LOCATION, and partial access on Android 14 needs READ_MEDIA_VISUAL_USER_SELECTED (the app handles limited access at `home_screen.dart:159`). Any image permission would need its own justification that you cannot give. | `apps/video_player/android/app/src/main/AndroidManifest.xml:6-9` | In App bundle explorer, remove unneeded ones with `tools:node="remove"`; keep READ_MEDIA_VIDEO (+ VISUAL_USER_SELECTED). |
| 5 | "Play from a link" pre-fills the box from the clipboard each time it opens; Android 12+ shows a "pasted from clipboard" toast. Not a violation. | `apps/video_player/lib/src/screens/network_dialog.dart:11` | Optional: only read the clipboard when the user taps a "Paste" button. |
| 6 | Link playback and watch parties can be used with pirated streams. Play judges the listing: don't suggest movies/TV, don't preload any links. | `apps/video_player/lib/src/screens/network_dialog.dart` | Listing text above stays neutral. |
| 7 | Firebase rules for `watch/` exist only on branch `ludo-game` (`firebase/database.rules.json`). | - | Deploy them before release; without them online rooms fail (locked DB) or are open. |
