# Vacancy Bell: Sarkari Job Alert - Play Console sheet

- Folder: `apps/vacancy_bell` - Package: `in.onlysoftware.vacancy_bell`
- Type: App - Free - **No ads in version 1** - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/vacancy_bell.html

What the code really does: downloads one public job list (`jobs/index.json`, plus one file per post when opened) from the `feed-data` branch of `hemantpatle153-ops/ad-apps-builds` on GitHub (`AppConfig.feedBaseUrl`, ETag cache, works offline from the last copy). Tabs by post type (Jobs, Admit Card, Result, Answer Key, Syllabus, Admission, Notice), search, filters (qualification, state, category, only posts you can apply for, hide closed), sort by newest or closing soon. Detail page with dates, fees, age limit, vacancies, eligibility text, selection steps and links to the recruiting body's own site. Optional "My details" (date of birth, qualification, category, PwBD, ex-serviceman, state, gender) stay on the phone and power an eligibility hint and an age calculator. Saved posts, exam calendar, reminders 3 days and 1 day before the last date (local notifications, inexact alarms), and a background check about every 3 hours (WorkManager) that notifies about new posts. "Report a mistake" writes one record to Firebase Realtime Database `feedReports/` after anonymous sign-in, limited to 10 a day on the phone. Hindi and English.

## 1. Store listing

**App name** - the requested name is 31 characters, one over Play's 30-character limit:
```
Vacancy Bell: Sarkari Job Alert
```
Use one of these instead (pick before the first upload; the launcher label stays "Vacancy Bell"):
```
Vacancy Bell: Sarkari Jobs
```
(26/30) or `Vacancy Bell: Sarkari Naukri` (28/30) or `Vacancy Bell: Job Alerts` (24/30).

**Short description** (79/80)
```
Sarkari job alerts in Hindi & English: last dates, eligibility check, reminders
```

**Full description** (about 2100/4000)
```
Vacancy Bell helps you keep track of government job notices in one simple list, in Hindi or English.

FIND POSTS FAST
- Separate tabs for Jobs, Admit Cards, Results, Answer Keys, Syllabus, Admissions and Notices.
- Search in Hindi or English.
- Filter by qualification (10th, 12th, ITI, diploma, graduate and more), state and category: SSC, railways, banking, police, defence, teaching, state PSC, PSU and others.
- Sort by newest or by last date, and hide posts that have closed.

NEVER MISS A LAST DATE
- Clear labels: New, 3 days left, Last day today, Closed.
- Save a post and get a reminder 3 days and 1 day before its last date.
- An exam calendar shows upcoming last dates and exam dates month by month.
- Optional alerts when new posts are added for the categories you choose.

CHECK IF YOU CAN APPLY
Add your date of birth, qualification and category once. Vacancy Bell shows which posts match your qualification and age, including the usual age relaxation for OBC, SC/ST and PwBD in central government posts. When a rule is unclear it says "Check notice" instead of guessing. A handy age calculator tells your exact age on any date.

FULL DETAILS IN ONE PLACE
Important dates, application fee, age limit, vacancy break-up, eligibility, selection process and links to the official notice and website of the recruiting body.

WORKS ON SLOW INTERNET
The list is small and saved on your phone, so the last copy opens even without a connection.

FOUND A MISTAKE?
Tap "Report a mistake" on any post and we will check it.

IMPORTANT
Vacancy Bell is an independent app. It is not affiliated with, endorsed by or acting for any government, ministry, department, commission or recruitment board. Information is taken from public notices on official websites such as ssc.gov.in, upsc.gov.in, indianrailways.gov.in, rrbcdg.gov.in, ibps.in, nta.ac.in, employmentnews.gov.in and state public service commission websites. Always confirm every date, fee and rule in the original notice on the recruiting body's own website before you apply or pay. Vacancy Bell never asks for money, does not accept applications and cannot get anyone a job.

Free, no sign-up, no ads.
```

**Hindi listing (hi-IN), optional but recommended**

Short description:
```
सरकारी नौकरी अलर्ट हिंदी और अंग्रेज़ी में: अंतिम तिथि, पात्रता जांच, रिमाइंडर
```
For the full Hindi description, translate the English text above section by section; keep the IMPORTANT paragraph word for word in meaning.

**Category:** Education (alternatives: Productivity, News & Magazines is **not** advised: it triggers the News declaration).
**Tags:** Jobs, Education, Exam preparation, Reminders.
**Contact email:** the developer email (shown on the listing).

## 2. Government information policy (read before submitting)

Play's policy on government information and misrepresentation applies because the app shows government job information:

- [ ] The listing (above) and the app both say clearly that the app is **not** a government app and is not affiliated with any government body. In the app: first card on **More > Disclaimer & sources**, and Settings > About.
- [ ] The listing and the app name the **sources** (official websites). In the app: **Disclaimer & sources** lists them with links.
- [ ] No government emblem, Ashoka lion, state seals, ministry logos, flag, or the word "Official" in the name, icon, feature graphic or screenshots. The icon is a bell on an indigo square (`tool/generate_icons.py`).
- [ ] Screenshots must not show a notice PDF with an emblem. Use the list, filter and detail screens.
- [ ] **Government apps** question in App content: **No**.
- [ ] Do not write "Sarkari Result official", "Govt approved" or similar anywhere.

## 3. Data safety

Job list downloads are anonymous public file requests (no account, no IDs sent). "My details", saved posts, reminders and settings stay on the phone = **not collected**. Only "Report a mistake" sends data, and only when the user sends a report.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| App activity > Other user-generated content | Yes | No | No | **Optional** | App functionality (fix listing errors) | Report note the user types (max 300 characters), with post id and reason |
| Device or other IDs | Yes | No | No | **Optional** | App functionality, Fraud prevention/security | Firebase anonymous user ID, only when a report is sent |
| Personal info (name, email, phone, address) | No | No | - | - | - | - |
| Personal info > Other info (date of birth, category, PwBD) | **No** | No | - | - | - | Stays on the phone, never uploaded |
| Location | No | No | - | - | - | No location permission; state is typed by the user and stays on the phone |
| All other types | No | No | - | - | - | - |

- Encrypted in transit: **Yes** (HTTPS to GitHub and Firebase).
- Deletion request: users can ask by email (the anonymous ID is not linked to them; reports are deleted after review). Uninstall deletes everything on the phone.
- No advertising ID: release builds made without `ADS=on` remove the `AD_ID` permission and the Mobile Ads init provider (`android/app/src/noads/AndroidManifest.xml`). **Advertising ID declaration: No.** Check this in App bundle explorer > Permissions after the first upload.

## 4. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| INTERNET | "Downloads the public job list and sends reports the user chooses to send." | No |
| POST_NOTIFICATIONS | "Shows last-date reminders for saved posts and new-post alerts the user turns on. Asked after an in-app explanation." | No |
| RECEIVE_BOOT_COMPLETED | Re-creates scheduled reminders and the background check after a restart. | No |
| ACCESS_NETWORK_STATE, WAKE_LOCK | Added by AndroidX WorkManager for the background check (runs only with a network connection). | No |
| AD_ID | **Removed** in release builds without ads. | Advertising ID: **No** |

`FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SHORT_SERVICE` (declared by the workmanager plugin) are removed in the app manifest because the alert check never runs as a foreground service, so **no foreground service declaration**. No `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` (reminders use inexact alarms), so **no exact alarm declaration**.

## 5. Content rating (IARC)

- Category: **Reference, News, or Educational**.
- All content questions: **No**. Gambling: **No**.
- Users interact or share content with each other: **No** (reports go only to the developer). Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 6. Ads, audience and other declarations

- Contains ads: **No** (version 1). If a later version is built with `--dart-define=ADS=on`, switch this to Yes, the Advertising ID answer to Yes, add the AdMob rows from another sheet (for example `water_habit.md`) to Data safety, and update `website/build.py` (`NO_ADS`) before uploading.
- Target audience: **16-17, 18 and over** (job seekers). 13-15 is acceptable too; do not tick any under-13 group.
- Government apps: **No** (see section 2). News app: **No**. Financial features: **None**. Health: **None**.
- App access: all functionality is available without special access.

## 7. Before release

- [ ] The feed is live at `https://raw.githubusercontent.com/hemantpatle153-ops/ad-apps-builds/feed-data/jobs/index.json`. Without it the app shows the error screen. A different host can be set at build time with `--dart-define=FEED_BASE_URL=https://.../` (trailing slash).
- [ ] Register the Android package `in.onlysoftware.vacancy_bell` in Firebase project `dice-dhamaal` and build with `--dart-define=FIREBASE_APP_ID=<its app id>` (the code falls back to Expense Tracker's app id, which works for the database but mixes analytics of the two apps).
- [ ] Enable Anonymous sign-in in Firebase Authentication (already on for the other apps) and deploy the rules with the new `feedReports` section: `firebase deploy --only database`.
- [ ] Deploy the privacy page (`python website/build.py`, `firebase deploy --only hosting`) and open the link.

## 8. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| Store name over 30 characters. | section 1 | Pick one of the shorter names. |
| A wrong date or fee in the feed could mislead users. | feed data | The app always tells users to verify on the official site and links to it; act on `feedReports` quickly. |
| Background check every 3 hours. Android may run it later on battery saver; not a policy issue. | `lib/services/background.dart` | Users can turn alerts off in Settings. |
| The Firebase app id is shared with Expense Tracker until a separate one is registered. | `lib/data/report_backend.dart` | See section 7. |
