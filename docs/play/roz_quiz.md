# Roz Quiz - Play Console sheet

- Folder: `apps/roz_quiz` - Package: `in.onlysoftware.roz_quiz`
- Type: App - Free - **No ads in the first release** (built with the default `ADS=off`) - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/roz_quiz.html (from `website/build.py`; deploy hosting before filling the forms)
- Uses Firebase project **dice-dhamaal** (Anonymous Auth, Realtime Database path `feedReports/`, write-only). The app id in `lib/services/firebase_reports.dart` is borrowed from Expense Tracker: **register `in.onlysoftware.roz_quiz` in the Firebase project and put its own app id there before release.**
- Feed: daily quiz, current affairs and question banks are read from the `feed-data` branch of `ad-apps-builds` (`AppConfig.feedBaseUrl`, override with `--dart-define=FEED_BASE_URL=...`).

What the code really does: a 10-question bilingual (English/Hindi) Daily Quiz each day (from the feed; offline, the same 10 questions for everyone from the bundled bank of 192 questions); instant answer feedback with explanations; streaks, XP, levels and 14 badges; a heatmap of played days; Current Affairs notes as vertical swipe cards with a quiz at the end; practice by subject or exam with length, difficulty and previous-year-only filters, without repeating questions until a set is used up; timed mock tests (25/50/100 questions, 36 s per question) with a question palette, mark for review, clear response and negative marking (none, 1/4, 1/3, 1/2) and section-wise analysis; stats per subject with weak topics; bookmarks and an automatic "My mistakes" list with revision; past daily quizzes; local reminders (8:00 AM IST by default) and a streak-at-risk nudge at 8:00 PM IST; "Report a mistake" for any question; light/dark theme; text up to 1.3x. No sign-up, no payments, no chat, no user-visible content from other users.

How to build the bundle: `cd apps/roz_quiz && flutter build appbundle --release` with `android/key.properties` in place (ADS stays off, so no AdMob IDs are needed). `tool/build_release.ps1` does not list Roz Quiz yet because it always passes AdMob IDs; add it there when the app gets ads.

## 1. Store listing

**App name** (30/30)
```
Roz Quiz: Daily GK & Exam Quiz
```

**Short description** (79/80)
```
10 GK questions a day in Hindi & English. Streaks, mock tests, current affairs.
```

**Full description** (2162/4000)
```
Roz Quiz gives you 10 fresh general knowledge questions every day, in English and Hindi. Play in two minutes, keep your streak alive and get ready for SSC, Railway, Banking, UPSC, State PSC, Defence and Teaching exams.

DAILY QUIZ
- 10 new questions every morning, the same for everyone.
- See the right answer and a short explanation right after each question.
- Share your score with friends.
- Works offline too: a built-in question bank keeps the daily quiz going without internet.

HINDI AND ENGLISH
Switch the whole app between Hindi and English, or tap the translate button to see one question in the other language.

STREAKS, XP AND BADGES
Play every day to grow your streak. Earn XP for every answer, level up and collect badges. A calendar heatmap shows the days you played.

CURRENT AFFAIRS
Short notes on recent events as swipe cards, with the source named. Finish the cards and take a quick quiz on them.

PRACTICE
- Practise by subject: GK, History, Polity, Geography, Economy, Science, Current Affairs, Maths, Reasoning, English and Computer.
- Or by exam.
- Choose 10, 20 or 30 questions and easy, medium or hard.
- Previous-year questions filter, when they are available.
- Questions do not repeat until you have seen the whole set.

MOCK TESTS
Timed tests of 25, 50 or 100 questions with a question palette, mark for review, clear response and negative marking (1/4, 1/3 or 1/2). After submitting, see your score, accuracy and a section-wise analysis.

TRACK YOUR PROGRESS
Accuracy for every subject, your weak topics, the last 14 days and your total time spent. Bookmark questions and revise the ones you got wrong in "My mistakes".

REMINDERS
A gentle daily reminder at 8:00 AM (change the time or turn it off) and a nudge in the evening when your streak is about to break.

REPORT A MISTAKE
Found a wrong answer or a bad translation? Report it from the question and we will check it.

PRIVATE AND LIGHT
No sign-up and no ads. Your scores and progress stay on your phone.

Roz Quiz is an independent practice app. It is not affiliated with SSC, RRB, IBPS, UPSC, any State PSC or any government body. Current affairs notes name their sources.
```

**Category:** Education
**Tags:** Quiz, General knowledge, Exam preparation, Trivia, Education

## 2. Data safety

Scores, streaks, stats, XP, badges, bookmarks, mistakes, seen questions and settings stay on the phone = **not collected**. Feed downloads are plain GETs of public files; they send no user data = not collected.

"Report a mistake" sends a report to Firebase Realtime Database `feedReports/` after anonymous sign-in = **collected** (optional, user-initiated), not shared (Firebase is a service provider). Fields: `app` ("roz_quiz"), `item` (question id), `reason` (wrong_answer / wrong_question / translation / other), `note` (optional, up to 300 characters, typed by the user), `by` (anonymous Firebase uid), `at` (server time).

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Personal info > User IDs | Yes | No | No | Optional | App functionality, Fraud prevention/security | Anonymous Firebase uid in a report |
| App activity > Other user-generated content | Yes | No | No | Optional | App functionality | The report's reason and note |
| Device or other IDs | No | No | - | - | - | AD_ID permission removed; no ads, no analytics |
| Location | No | No | - | - | - | - |
| All other types | No | No | - | - | - | - |

- Encrypted in transit: **Yes**.
- Users can request deletion: **Yes**, by writing to the developer email (reports hold only an anonymous id; quote the question and date). Data on the phone is deleted by uninstalling the app or clearing its data.
- No account, so no account-deletion link is needed.

## 3. Permissions and declarations

| Permission | Why | Play form? |
|---|---|---|
| INTERNET | Download the daily quiz, current affairs and banks; send reports. | No |
| POST_NOTIFICATIONS (Android 13+) | Daily reminder and streak nudge. Asked only after an explanation screen; the app works fully without it. | No |
| RECEIVE_BOOT_COMPLETED | flutter_local_notifications re-creates scheduled reminders after a reboot. | No |
| AD_ID | **Removed** in the manifest (`tools:node="remove"`). Advertising ID question: **No**. | Advertising ID form: No |

No exact alarms (reminders are inexact on purpose), no camera, storage, contacts or location.

## 4. Content rating (IARC)

- Category: **Reference, News, or Educational**.
- Violence, sexuality, language, controlled substances, gambling: **No**.
- Users interact: **No** (reports go only to the developer; nothing is shown to other users). Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **No** for this release. The AdMob SDK is in the binary through `app_core` but is never initialised while `ADS=off`. When ads are turned on later: build with `--dart-define=ADS=on`, the real AdMob IDs and `-PadmobAppId`, delete the AD_ID removal line in the manifest (the release build refuses otherwise), and update this sheet, the Data safety form and the privacy page.
- Target audience: **13-15, 16-17, 18+**.
- News app: **No** (current affairs notes are short study notes with a named source, not a news service).
- Government apps: **No**. Financial features: none. Health: none.

## 6. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| Looking like an official exam body. | Listing, in-app text | The listing and the About / Sources pages say the app is independent; keep exam logos out of screenshots. |
| A wrong answer in the bundled bank is shown offline to everyone. | `apps/roz_quiz/assets/bank/` | `test/bank_integrity_test.dart` checks every question; fix reported questions in the feed and in the bank. |
| The Firebase app id is not Roz Quiz's own. | `apps/roz_quiz/lib/services/firebase_reports.dart` | Register the package in Firebase and replace it before release. |
| `feedReports` writes are rejected unless the database rules allow `app: "roz_quiz"`. | `firebase/database.rules.json` (separate PR) | Deploy the rules before release. |
| Privacy page must be live. | `website/build.py` | Run `python website/build.py` and deploy hosting. |
| Play may detect the Google Mobile Ads SDK and ask about ads. | `packages/app_core` | Answer "No ads": the SDK is never initialised and the AD_ID permission is removed. |
