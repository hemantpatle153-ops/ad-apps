# Vacancy Bell

Sarkari job alerts in Hindi and English (Play name: see `docs/play/vacancy_bell.md`).
Post tabs, search and filters, an eligibility check from optional "My details",
an age calculator, saved posts, an exam calendar, last-date reminders (3 days and
1 day before, 9 AM India time by default), new-post alerts every ~3 hours, and
"Report a mistake". Not affiliated with any government body; the app says so in
Disclaimer & sources.

See the repository README for build and release steps.

## Job feed

The app reads a public feed (the schema lives with the feed generator):

- `jobs/index.json` - every post's summary, refreshed with ETag / 304.
- `jobs/posts/<id>.json` - one post's full details, fetched when opened.

Base URL: `AppConfig.feedBaseUrl` in `lib/config.dart`
(`https://raw.githubusercontent.com/hemantpatle153-ops/ad-apps-builds/feed-data/`).
Point a build at another copy with `--dart-define=FEED_BASE_URL=https://host/path/`
(keep the trailing slash). The last good copy is cached on the phone, so the app
opens offline. Parsing is defensive: bad entries are skipped, a bad file falls
back to the cache, and a feed with a newer `schema` shows an "update the app" note.

## Ads

Version 1 ships **without ads**. Ads are controlled by one build flag:

- default (`ADS` unset or `off`): no ad SDK start, no banner, and release builds
  merge `android/app/src/noads/AndroidManifest.xml`, which removes the `AD_ID`
  permission and the Mobile Ads init provider. `bundleRelease` needs no AdMob IDs
  (`tool/build_release.ps1` lists the app in `$adFree`).
- `--dart-define=ADS=on`: banner above the bottom bar like the other apps; a
  bundle build then requires `-PadmobAppId` and the `ADMOB_*` dart-defines.
  Remove the app from `$adFree`, add it to `admob.json`, and update the Play
  sheet and the privacy page (`website/build.py`) first.

## Reports

"Report a mistake" signs in anonymously to Firebase project `dice-dhamaal` and
pushes `{app, item, reason, note, by, at}` to `feedReports/` (rules and tests in
`firebase/`). The phone allows 10 reports a day and one per post and reason.
Register this package in Firebase and pass `--dart-define=FIREBASE_APP_ID=...`;
until then the code uses Expense Tracker's app id.

## Code map

- `lib/models`, `lib/core` - feed parsing, dates in India time.
- `lib/logic` - eligibility engine, search/filter/sort, alerts, reminder plan,
  calendar, reports, share text (pure Dart, unit tested).
- `lib/data` - HTTP fetcher, file cache, repository, settings.
- `lib/services` - notifications, WorkManager background check, sync.
- `lib/state/app_controller.dart` - app state used by `lib/ui`.
- `lib/l10n` - all strings in English and Hindi.

Tests: `flutter test` (fixtures in `test/fixtures`, fakes in `test/support`).
