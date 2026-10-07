# Multi Speaker - Play Console sheet

> **First release has ads off** (`--dart-define=ADS=off`): ignore every AdMob row and ad answer below; see [README](README.md). They apply once ads are turned on.

- Folder: `apps/multi_speaker` - Package: `in.onlysoftware.multi_speaker`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/multi_speaker.html

What the code really does: one phone **hosts a party** and the other phones **join** on the same Wi-Fi or the host's hotspot (scan the host's QR code with the camera, pick a party found nearby, or type the address). **Songs mode**: the host picks audio files from the phone; the host serves them to the guests over the local network (HTTP + WebSocket), and all phones play in sync (clock sync). **Live mode** (Android 10+): the host captures the sound other apps are playing (Android playback capture via MediaProjection, foreground service) and streams it live to the guests. Each phone plays on its own speaker (built-in, wired or Bluetooth); per-phone delay settings fix Bluetooth lag; the host can remove a speaker. Background playback with a media notification. A help page explains other ways to use many Bluetooth speakers (Dual audio, speaker party modes). No internet is used for the music; only ads use the internet.

## 1. Store listing

**App name** (25/30)
```
Multi Speaker: Sync Music
```

**Short description** (77/80)
```
Play the same music on many phones and speakers at once, in sync, over Wi-Fi.
```

**Full description** (1783/4000)
```
Make your party louder with the phones you already have. Multi Speaker plays the same song on several phones at the same moment, and each phone can drive its own speaker.

HOW IT WORKS
1. Put all phones on the same Wi-Fi, or on the host phone's hotspot.
2. On one phone tap "Host a party".
3. On the other phones tap "Join a party" and scan the host's QR code, or pick the party from the list.
4. Connect each phone to its own speaker and press play.

SONGS MODE
The host picks music files from the phone. The songs are sent straight to the other phones over your own Wi-Fi and everyone plays in sync. No internet and no account needed for the music.

LIVE MODE (Android 10 and newer)
Send whatever the host phone is playing, from a music app, a video or a game, to every speaker in the party. Android asks for permission to capture the phone's sound; only sound is sent, never the screen. Some apps block their sound from being captured; then the speakers stay quiet.

STAY IN SYNC
- Phones keep a shared clock so the music lines up.
- Bluetooth speakers add their own delay. Set the delay for the phone speaker and for Bluetooth so every speaker matches.
- Music keeps playing with the screen off, with controls in the notification.
- If a phone loses the connection for a moment, it reconnects by itself.

MORE THAN ONE SPEAKER ON ONE PHONE?
A help page explains your options, such as Dual audio on some phones and the party modes built into many Bluetooth speakers.

PRIVATE
Music only travels on your own local network, directly between your phones. It never goes to our servers. No ads.

Tip: Wi-Fi quality matters. For the best sync, keep the phones close to the router or use the host phone's hotspot.
```

**Category:** Music & Audio
**Tags:** Music player, Speaker, Party, Bluetooth, Audio

Do **not** write YouTube, Spotify, Netflix, JBL or Samsung in the store text or show their logos in screenshots (impersonation / IP rules).

## 2. Data safety

- Music files and live sound go **directly from the host phone to the guest phones on the same local network**. They never reach you (the developer) or any third party, and nothing is stored. Recommended answer: **not collected** (same as a direct phone-to-phone transfer the user starts). If a reviewer asks, explain this in the "Additional info" box; the privacy policy says the same.
- The phone's name (or the name typed in Settings) is shown to the other phones in the party, on the local network only = not collected.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK; ML Kit barcode scanning (join QR) sends usage metrics |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID; ML Kit install ID |
| Audio (voice, music files, other audio) | No | No | - | - | - | Local Wi-Fi only, phone to phone, not stored |
| All other types | No | No | - | - | - | - |

- Encrypted in transit: **Yes** for everything that is collected (AdMob/ML Kit use HTTPS). The local music stream is plain HTTP on the user's own network and is not "collected".
- Deletion request: **No** (no account, nothing stored by you).

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| FOREGROUND_SERVICE_MEDIA_PLAYBACK (service `com.ryanheise.audioservice.AudioService`, type `mediaPlayback`) | See declaration A below. | **Foreground service** declaration |
| FOREGROUND_SERVICE_MEDIA_PROJECTION (service `.CaptureService`, type `mediaProjection`) | See declaration B below. | **Foreground service** declaration |
| RECORD_AUDIO | "Android requires this permission to capture the sound that other apps play (Live mode, AudioPlaybackCapture). The microphone is not recorded; only playback sound from media and games is captured, and only while Live is on." | No form; Play shows "Microphone" on the listing. |
| CAMERA | "Used only to scan the host phone's QR code to join a party." | No form |
| POST_NOTIFICATIONS | Shows the playback controls and the "Sending this phone's sound" notification. | No form |
| ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE, ACCESS_NETWORK_STATE, WAKE_LOCK, INTERNET | Find parties on the local Wi-Fi, keep Wi-Fi awake during the party, ads. | No form |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

**Declaration A - Media playback**
> Multi Speaker plays music in sync on several phones. On guest phones (and on the host in Songs mode) the music must keep playing when the user turns the screen off or switches apps, with play/pause controls in the media notification. The service runs only while a party is playing and stops when the user leaves the party. If the service were stopped, the music on that speaker would cut out in the middle of the party.

Video to record (30-60 s, upload to YouTube as Unlisted or Google Drive "anyone with link"): open the app on two phones > Host a party > add a song > Join on the second phone by scanning the QR > press Play > lock the screen of the guest phone and show the music continues > show the notification with play/pause.

**Declaration B - Media projection**
> In Live mode the host phone sends the sound that other apps are playing to the other phones in the party. Android only allows this playback capture from a foreground service of type mediaProjection after the user taps "Start live" and agrees in the system "Start recording or casting?" dialog. Only audio is captured (AudioPlaybackCaptureConfiguration with media/game usages); the screen is never recorded and nothing is saved. The user can stop it any time from the app or the system cast notification.

Video to record (30-60 s): host phone > Host a party > Live tab > tap "Start live" > show the system dialog and tap "Start now" > open a music app and play > show the guest phone playing the same sound > tap Stop.

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other** (or Music).
- Violence, sexuality, language, drugs, gambling: **No**. (Users can play any music they own; that is user content on their own phones, not app content.)
- Users interact or exchange content: **No** for online interaction (no chat, no accounts; only phones on the same local network join, and only music is sent). If you want to be extra safe answer **Yes - users can share content**; the rating stays Everyone with a "Users Interact" note.
- Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - one banner at the bottom of the home, host, guest and join screens (never over buttons); interstitial only when a party ends or a guest leaves (2-minute gap).
- Target audience: **13-15, 16-17, 18+**.
- Financial: none. Health: none. Government: No. News: No.

## 6. Policy risks found in the code

| # | Risk | Where | What to do |
|---|---|---|---|
| 1 | Two foreground-service types (mediaPlayback, mediaProjection) need Play Console declarations **with videos**, or the release is blocked. | `apps/multi_speaker/android/app/src/main/AndroidManifest.xml:9-11, 44-54` | Fill both declarations with the text and videos above. |
| 2 | In-app text names other apps' brands: "Open YouTube or any app and press play", "YouTube, music apps, games", "Netflix"; help page names JBL and Samsung. Fine as plain help text, but **don't** use these names/logos in the store listing or screenshots. Live mode re-broadcasts other apps' audio; keep the listing about "your own music and sound", never "share YouTube/Spotify songs". | `apps/multi_speaker/lib/src/ui/host_screen.dart:287-288, 339, 353`, `apps/multi_speaker/lib/src/ui/bluetooth_help_screen.dart:29-30, 76-81` | Optional: change in-app text to "a video app" to avoid any IP complaint. |
| 3 | RECORD_AUDIO makes Play show "Microphone" access. The in-app explanation exists on the Live tab before the request ("Android asks to record or cast this phone... Only sound is sent, never your screen"). | `apps/multi_speaker/android/app/src/main/AndroidManifest.xml:12`, request at `android/app/src/main/kotlin/in/onlysoftware/multi_speaker/MainActivity.kt:105-106`, text at `lib/src/ui/host_screen.dart:331-334` | OK. Mention in the listing that only sound is captured (done). |
| 4 | `usesCleartextTraffic="true"` for the whole app (needed for local http/ws). Security scanners and the pre-launch report may warn. | `apps/multi_speaker/android/app/src/main/AndroidManifest.xml:19` | Optional: replace with a `network_security_config` that allows cleartext only for local IP ranges. Not a rejection reason. |
| 5 | POST_NOTIFICATIONS is declared but never requested at runtime, so on Android 13+ the Live-mode notification "Sending this phone's sound" may be hidden. The system cast indicator still shows, so users are not misled, but ask for the permission when Live starts. | `apps/multi_speaker/android/app/src/main/AndroidManifest.xml:13`, `android/app/src/main/kotlin/in/onlysoftware/multi_speaker/CaptureService.kt:144` | Request POST_NOTIFICATIONS before starting a party. |
| 6 | The phone's system device name (can contain the owner's real name) is shown to other phones by default. | `apps/multi_speaker/lib/src/ui/host_screen.dart:51`, `lib/src/ui/guest_screen.dart:46` | Local network only, low risk. Users can change it in Settings. |
