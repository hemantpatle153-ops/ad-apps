# Water Reminder & Habit Tracker - Play Console sheet

> **First release has ads off** (`--dart-define=ADS=off`): ignore every AdMob row and ad answer below; see [README](README.md). They apply once ads are turned on.

- Folder: `apps/water_habit` - Package: `in.onlysoftware.water_habit`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://docs.google.com/document/d/e/2PACX-1vSA3p-UvHEj2L2nIDLYeWIFo39PWUj8HU8qngDsyVkl4Eu_VXmlRnF8oBbCmL7SJ98_ziBsZA_iXNnN/pub

What the code really does: Water tab - daily goal (1500-4000 ml), glass size (150-500 ml), one-tap add a glass or a custom amount, progress, "Goal reached!" message and a water streak. Reminders - local notifications between wake-up and bed time, every 1, 1.5, 2 or 3 hours (inexact alarms, no exact-alarm permission). Habits tab - add your own habits (for example "Read 10 pages"), tick them off each day, streaks, optional daily reminder per habit. All data on the phone. The notification permission is asked on first launch.

## 1. Store listing

**App name** (30/30)
```
Water Reminder & Habit Tracker
```

**Short description** (77/80)
```
Drink enough water with gentle reminders and build daily habits with streaks.
```

**Full description** (1194/4000)
```
Two simple trackers in one app: how much water you drink, and the small daily habits you want to keep.

WATER
- Set a daily goal from 1500 to 4000 ml and your usual glass size.
- Tap once to log a glass, or enter any amount.
- See your progress for today and keep your streak going.
- A small celebration when you reach your goal.

REMINDERS THAT FIT YOUR DAY
Set your wake-up time and bed time and choose how often to be reminded: every 1, 1.5, 2 or 3 hours. Reminders come only between those times. You can turn them off any time.

HABITS
- Add any habit: a walk, reading, stretching, studying, prayer, anything.
- Tick it off each day and watch your streak grow.
- Add an optional daily reminder for each habit.

SIMPLE AND PRIVATE
No account and no cloud. Your log, habits and reminder times are stored only on your phone, and reminders are scheduled on the phone too. No ads.

Note: this app is a personal tracker and reminder tool. It is not a medical device and does not give medical advice. How much water you need depends on your body, the weather and your activity; ask a doctor if you have a health condition.
```

**Category:** Health & Fitness
**Tags:** Water tracker, Drink water reminder, Habit tracker, Reminders, Health & fitness

## 2. Data safety

Water log, habits, streaks and reminder times stay on the phone = **not collected**. Notifications are scheduled locally (no push server).

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID |
| Health and fitness (health info, fitness info) | **No** | No | - | - | - | Water amounts and habits stay on the phone |
| All other types | No | No | - | - | - | - |

- Encrypted in transit: **Yes**.
- Deletion request: **No** (no account; uninstall or clear app data deletes everything; single habits can be deleted in the app).

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| POST_NOTIFICATIONS | "Shows the water and habit reminders the user turns on. Reminders are scheduled on the phone." | No form |
| RECEIVE_BOOT_COMPLETED | Re-creates the scheduled reminders after the phone restarts (flutter_local_notifications). | No form |
| INTERNET | Ads only. | No |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

No `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` (inexact alarms on purpose, `lib/reminders.dart:9-10, 77`), so **no exact alarm declaration** is needed. No foreground service.

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other**.
- All content questions: **No**. Gambling: **No**.
- Users interact: **No**. Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner; interstitial after the daily water goal is reached or after a new habit is added (2-minute gap).
- Target audience: **13-15, 16-17, 18+**.
- **Health apps declaration**: the app tracks water intake, so tick the closest feature, usually **"Nutrition and weight management"** (diet/hydration tracking). Do **not** tick medical, disease management, clinical or "medical device" items. Habits are general self-improvement, not health features. The app does not use Health Connect, so no Health Connect form.
- Medical claims: none. Never write "detox", "cures", "lose weight fast" or similar in the listing.
- Financial: none. Government: No. News: No.

## 6. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| Notification permission is requested on the very first launch, before the user has seen the app or turned reminders on, with no in-app explanation. Not a Play violation, but Android guidance asks for context, and many users press "Don't allow". | `apps/water_habit/lib/main.dart:59-62` | Show a small card first ("Get reminders to drink water? Allow notifications") and ask only when the user taps Yes, or when they turn on a reminder (already done at `settings_screen.dart` and `habits_view.dart:74`). |
| Name mismatch: launcher label "Water Reminder", in-app title "Water & Habit Reminder", store name "Water Reminder & Habit Tracker". | `apps/water_habit/android/app/src/main/AndroidManifest.xml:6`, `apps/water_habit/lib/main.dart:31` | Not a violation. Keep "Water Reminder" first everywhere. |
| Health wording risk in the listing only (no risky claim in the app). | - | Keep the "not a medical device" note in the description. |
