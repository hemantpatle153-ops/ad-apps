# Roz Quiz

Daily GK quiz, current affairs notes and exam practice (SSC, Railway, Banking,
UPSC, State PSC, Defence, Teaching) in English and Hindi. Works offline with a
bundled starter bank; fresh daily quizzes, current affairs and banks come from
the public feed described in `ad-apps-builds/feeds/SCHEMA.md`.

```
flutter test
flutter run                                                    # ads off (first release)
flutter run --dart-define=FEED_BASE_URL=http://10.0.2.2:8000/  # a local copy of the feed
flutter run --dart-define=ADS=on                               # with (test) ads
```

The starter bank lives in `assets/bank/*.json` (same format as the feed's
`quiz/banks/<subject>.json`); `test/bank_integrity_test.dart` checks every
question in it.

See the repository README for build and release steps.
