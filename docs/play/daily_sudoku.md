# Daily Sudoku - Play Console sheet

> **First release has ads off** (`--dart-define=ADS=off`): ignore every AdMob row and ad answer below; see [README](README.md). They apply once ads are turned on.

- Folder: `apps/daily_sudoku` - Package: `in.onlysoftware.daily_sudoku`
- Type: **Game** (Puzzle) - Free - Contains ads - Ages 13+
- Privacy policy: https://docs.google.com/document/d/e/2PACX-1vTaZv3owS5iiOH0PkLw7wnCHDw5u2rNyOyLbHogItpRQyKczECgA0o1FEJ3oDmwQxfkOijJHOj4tgtC/pub

What the code really does: a daily puzzle (the same puzzle for a given date, made on the phone), a daily streak, new games in 4 levels (Easy, Medium, Hard, Expert) with one unique solution, notes (pencil marks), undo, timer, 3 mistakes allowed, 3 free hints per puzzle and then an optional rewarded video for one more hint, "second chance" after the 3rd mistake, best time per level and puzzles-solved count, auto-save and Continue. Everything is stored on the phone; works offline (ads need internet).

## 1. Store listing

**App name** (12/30)
```
Daily Sudoku
```

**Short description** (77/80)
```
A new Sudoku every day, 4 levels, notes and hints. Build your streak offline.
```

**Full description** (1196/4000)
```
Daily Sudoku gives you a fresh puzzle every day and as many extra games as you like. Solve today's puzzle to grow your streak.

FOUR LEVELS
Easy, Medium, Hard and Expert. Every puzzle has exactly one solution, so you can always solve it with logic, no guessing needed.

TOOLS THAT HELP, NOT SOLVE
- Notes: write small candidate numbers in a cell. Notes in the same row, column and box clear themselves when you place a number.
- Undo your last moves.
- Hints: 3 free hints in every puzzle. Want one more? You can choose to watch a short video ad for an extra hint.
- Mistakes: you have 3 tries. After the third one you can quit or take a second chance.

TRACK YOUR PROGRESS
- Daily streak: how many days in a row you solved the daily puzzle.
- Best time for each level.
- Total puzzles solved.

PLAY ANY TIME
Your game is saved automatically. Close the app and tap Continue later. Puzzles are created on your phone, so you can play without internet.

CLEAN AND CALM
Simple design with light and dark theme. A small banner ad sits at the bottom. A full-screen ad can appear only after you finish or quit a puzzle, never in the middle of play.

No account needed. Your progress stays on your phone.
```

**Category:** Puzzle (Games)
**Tags:** Sudoku, Puzzle, Logic, Number, Brain games

## 2. Data safety

Game progress, streak and stats stay on the phone (SharedPreferences) = **not collected**. Only the AdMob SDK sends data.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (from IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (ad views, taps, rewarded views) |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID |
| Everything else (personal info, financial, photos, audio, files, contacts, messages, health, precise location) | No | No | - | - | - | - |

- Encrypted in transit: **Yes**.
- Deletion request: **No** (no account; progress is deleted by uninstalling or clearing app data).

## 3. Permissions and declarations

| Permission | Why | Play form? |
|---|---|---|
| INTERNET | Ads only. | No |
| AD_ID (from AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

No other permissions.

## 4. Content rating (IARC)

- Category: **Game** (puzzle).
- Violence, blood, fear, sexuality, language, drugs, crude humor: **No**.
- Gambling / simulated gambling: **No**. (Rewarded ads give a hint, not money or prizes.)
- Users interact with each other: **No**. Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner, interstitial after a finished/quit puzzle (2-minute gap), **rewarded** (user chooses to watch for an extra hint or a second chance).
- Target audience: **13-15, 16-17, 18+**. Sudoku is a general-audience puzzle; answer **No** to "appeals to children". Do not use cartoon/kid art in the icon or screenshots.
- Financial: none. Health: none. Government: No. News: No.

## 6. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| The **"Second chance" button does not say it plays an ad**, but tapping it starts a rewarded video. AdMob rewarded-ad policy needs the user to clearly agree to watch an ad before it starts. | `apps/daily_sudoku/lib/game_screen.dart:215` (button), `:229-231` (shows `showRewarded`) | Change the button text to "Watch ad for second chance" when `rewardedReady` is true (and "Second chance" only when it is free). Medium risk for AdMob account. |
| Extra hint flow is fine: it asks "Watch a short video to get one more hint?" first. | `apps/daily_sudoku/lib/game_screen.dart:136-151` | Keep as is. |
| Interstitial right after the "Solved!" dialog and after "Quit" is a natural break - fine. Cooldown of 2 minutes is in `packages/app_core`. | `apps/daily_sudoku/lib/game_screen.dart:201`, `:243` | Keep. |
