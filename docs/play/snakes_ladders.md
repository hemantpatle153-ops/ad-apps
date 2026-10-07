# Dice Dhamaal (Ludo + Snakes & Ladders) - Play Console sheet

> **First release has ads off** (`--dart-define=ADS=off`): ignore every AdMob row and ad answer below; see [README](README.md). They apply once ads are turned on.

- Folder: `apps/snakes_ladders`, **branch `ludo-game`** - Package: `in.onlysoftware.dice_dhamaal`
- Type: **Game** (Board) - Free - Contains ads - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/dice_dhamaal.html
- Uses Firebase project **dice-dhamaal** (Anonymous Auth + Realtime Database, path `rooms/{code}`) and WebRTC voice

Build and upload from `ludo-game`. The `main` branch still has the old offline-only "Snakes & Ladders" with package `in.onlysoftware.snakes_ladders` (`apps/snakes_ladders/android/app/build.gradle.kts:27` on main). The first upload fixes the package name forever.

What the code really does: one app, two games. **Ludo**: vs Computer (bots), Pass & Play on one phone (2-4 players), and **Play with Friends** online - create a room and share the 6-letter code, or join with a code; 2-4 players; rule options (Quick game with 2 pieces, only a 6 opens a piece, three sixes lose the turn); 5 board themes (Classic, Royal, Wood, Candy, Night); unfinished games saved. In online games **voice chat** is off until a player taps **Voice** (only then is microphone access asked); every phone connects directly to every other phone with WebRTC (encrypted with DTLS-SRTP, Google public STUN servers, no TURN relay); Firebase only passes the connection details. Buttons: mute my mic, speaker/earpiece, and per player **Mute** (stops audio both ways) and **Report** (stored under `reports` in Firebase until reviewed). **Snakes & Ladders (Saanp Seedhi)**: vs Computer or Pass & Play (2-4), 4 themes (Classic, Jungle, Neon Night, Candy), animated dice, sound effects, vibration, fast moves. No real money, no coins, no in-app purchases.

## 1. Store listing

**App name** (27/30)
```
Dice Dhamaal: Ludo & Snakes
```

**Short description** (79/80)
```
Ludo and Snakes & Ladders: play the computer, pass and play, or friends online.
```

**Full description** (1413/4000)
```
Dice Dhamaal brings two classic board games into one app: Ludo and Snakes & Ladders (Saanp Seedhi). Roll the dice, race your pieces home and have fun with friends.

LUDO
- Play vs Computer, with up to 3 computer players.
- Pass & Play: 2 to 4 players on one phone.
- Play with Friends online: create a room, share the 6-letter code, and your friends join from their own phones.
- Voice chat in online games: talk to the other players while you play. Tap Voice to turn it on. Calls go directly between the phones and are encrypted. Mute or report any player.
- House rules: Quick game (2 pieces each), only a 6 opens a piece, three sixes lose the turn.
- Board themes: Classic, Royal, Wood, Candy and Night.

SNAKES & LADDERS
- Play vs Computer or Pass & Play with 2 to 4 players.
- Animated dice, climbing ladders and sliding snakes.
- Board themes: Classic, Jungle, Neon Night and Candy.

MADE FOR FUN
- Sound effects and vibration you can turn off.
- Fast moves option for quicker games.
- Unfinished games are saved, so you can continue later.
- Offline games work without internet. Online rooms need internet.

FAIR AND FREE
There is no real money, betting, coins or prizes in this game. The app shows ads from Google AdMob; EU and UK users are asked for consent first.

PRIVACY
No account or sign-up. For online rooms the app uses a random anonymous ID and the name you type. Room data is deleted automatically. Voice is never recorded.
```

**Category:** Board (Games)
**Tags:** Ludo, Board, Dice, Multiplayer, Casual

Never use other games' names (for example "Ludo King") in the title, description or keywords.

## 2. Data safety

Offline games, settings and saved games stay on the phone = not collected. Online rooms use Firebase and voice goes over the internet = collected (optional, only if the user plays online).

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source / note |
|---|---|---|---|---|---|---|
| Personal info > Name | Yes | No | No | Optional | App functionality | Player name typed for online rooms (max 14 characters), shown to room players; room deleted within 6 h |
| Personal info > User IDs | Yes | No | No | Optional | App functionality, Fraud prevention/security | Random Firebase anonymous ID (database rules use it) |
| Audio > Voice or sound recordings | Yes | No | **Yes** | Optional | App functionality | Live voice chat, sent phone-to-phone over the internet, encrypted, never recorded or stored. Declaring it is the safe choice because it leaves the phone. |
| App activity > Other actions | Yes | No | No | Optional | App functionality | Game moves, seat, colour, online status in the room |
| App activity > Other user-generated content | Yes | No | No | Optional | Fraud prevention, security and compliance | Player reports: room code, reported player's name and seat, reason, reporter's anonymous ID, time. Kept only until reviewed. |
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address). (Other players' phones and Google STUN also see the IP during voice - mentioned in the privacy policy.) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID |
| Messages, Photos/videos, Files, Contacts, Financial, Health | No | No | - | - | - | - |

- Encrypted in transit: **Yes** (Firebase HTTPS, WebRTC DTLS-SRTP, AdMob HTTPS).
- Deletion request: **Yes** - rooms are deleted automatically (6 hours), reports after review; users can also write to the contact email. No user-visible account is created, so the account-deletion URL is not required.

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| RECORD_AUDIO | "Used only for voice chat with the other players in an online Ludo room, after the player taps Voice. Voice is sent directly and encrypted to the other players and is never recorded or stored." | No form; Play shows "Microphone" |
| MODIFY_AUDIO_SETTINGS | Switch between loudspeaker and earpiece during voice chat. | No |
| ACCESS_NETWORK_STATE, INTERNET | Online rooms, voice, ads. | No |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

No foreground service, no camera, no storage, no location permission.

## 4. Content rating (IARC)

- Category: **Game**.
- Violence: **No** (pieces are "cut" and sent home; no characters are hurt, no blood). Fear: **No** (cartoon snakes on a board, no horror).
- Sexuality, language, drugs, crude humor: **No**.
- **Gambling: No. Simulated gambling: No.** Dice decide moves in a classic board game; there is no betting, no casino games, no coins or chips, no real or virtual currency, no prizes.
- **Users can interact: Yes** - voice chat and player names in online rooms.
- Shares user's location: **No**.
- Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+ with "Users Interact" (some regions may give 7+/12 because of voice chat; that is fine).

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner on the hub, home, settings and game screens; interstitial only after a game ends (2-minute gap). No rewarded ads.
- Target audience: **13-15, 16-17, 18+**. Ludo and Snakes & Ladders are family games and the themes are colourful, so Play may ask if the app **appeals to children**. Answer **No** and keep the store art adult-neutral (no cartoon mascots, no "for kids" words). If Google decides it does appeal to children, you must follow the Families policy (child-safe ads, and voice chat with strangers would be a problem) - another reason for risks 1-2 below.
- App access: "Offline modes need nothing. To test online: Ludo > Play with Friends > Create room on phone 1, Join with the 6-letter code on phone 2, start the game, then tap Voice on both phones."
- Financial: none. Health: none. Government: No. News: No.

## 6. Policy risks found in the code (branch `ludo-game`)

| # | Risk | Where | What to do |
|---|---|---|---|
| 1 | **Fixed in PR #8 (d67a93d).** **Voice chat has no way to mute or block another player and no report option.** Only "mute my mic" and speaker/earpiece exist. Play's UGC policy (user-to-user communication) expects users to be able to block and report others. Anyone who gets the code (codes are often posted in groups) can join and talk. | `apps/snakes_ladders/lib/ludo/ui/game_screen.dart:630-645` (only self mute), `lib/ludo/online/voice.dart:185-195` | Add per-player **Mute** (set that peer's remote audio track `enabled=false`) on the player avatar, and a **Report** action (email with room code). Add a line in the lobby: "Only play with people you know." |
| 2 | **Fixed in PR #8 (d67a93d).** **Microphone turns on automatically when an online game starts** - no "Join voice" choice. The privacy policy says voice chat "is optional and uses the microphone only while it is on". | `apps/snakes_ladders/lib/ludo/ui/game_screen.dart:127` (`s.voice.start()`), policy text `website/build.py:100` | Start with the mic **muted** (or ask "Turn on voice chat?") and let the user unmute. Then the policy text is true. The lobby note at `lib/ludo/ui/online_screen.dart:241-242` already warns, which helps. |
| 3 | **Privacy policy URL is still the placeholder on this branch.** (The `main` working copy now points to the real page, but you build Dice Dhamaal from `ludo-game`.) | `apps/snakes_ladders/lib/main.dart:18-19` (branch `ludo-game`) | Set it to `https://dice-dhamaal.web.app/privacy/dice_dhamaal.html` on the `ludo-game` branch before building. |
| 4 | **Fixed in PR #8 (d67a93d):** BLUETOOTH_CONNECT was removed, so no "Nearby devices" prompt. | | |
| 5 | Player names are free text (14 chars) shown to others, no filter. | `apps/snakes_ladders/lib/ludo/ui/online_screen.dart:142` | Low risk; covered by the Report action in risk 1. |
| 6 | Voice uses only STUN (no TURN relay), so voice fails on some mobile networks. Not a policy issue, but don't promise "voice always works". | `apps/snakes_ladders/lib/ludo/online/voice.dart:20-31` | Listing text above does not promise it. |
| 7 | Store/launcher name: manifest label is "Dice Dhamaal" on the branch (good). On `main` the label is still "Snakes & Ladders". | `apps/snakes_ladders/android/app/src/main/AndroidManifest.xml:4` | Build from `ludo-game`. |
| 8 | Firebase rules must be deployed (`firebase/database.rules.json` on `ludo-game`) or online rooms fail. Firebase anonymous users pile up forever in Auth. | - | Deploy rules. Optional: in Firebase Auth settings enable automatic clean-up of anonymous accounts (needs Identity Platform upgrade) or leave as is (no personal data in them). |
