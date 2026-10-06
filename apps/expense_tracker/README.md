# Expense Tracker

Offline daily expense tracker with budget, insights and CSV export, plus
**Hisab**: a money log shared with a friend.

See the repository README for build and release steps.

## Hisab with friends

The Hisab tab keeps track of money lent and borrowed between two friends.

- **Start a hisab** with your name and your friend's. You get an 8 letter code
  (like `ABCD-2345`) to share.
- **Join with a code** on any number of phones; each phone says which of the
  two friends it belongs to, so both friends can use several phones.
- Each entry has an amount, who gave it, a purpose tag (Food, Loan, Trip, or
  your own), a note and a date that can be changed. Edits show who edited and
  when.
- The log shows the two lists ("Amit will give me" and "I will give Amit"),
  the totals and the final result: who gives whom, and how much. Both phones
  show the same result from their own side.
- **Reset code** replaces the join code; members, entries and confirmations
  stay.
- **Clearing**: one friend confirms the final amount, the other confirms the
  same amount, and the hisab is cleared. Any change in between cancels the
  confirmations. A cleared hisab is read-only for 14 days (it can be reopened,
  with a new code), then deleted from Firebase. Each phone keeps its own copy.

Code: `lib/hisab/` (`model.dart` holds the math and every database write;
`service.dart` the flows; `backend.dart` Firebase; `memory_backend.dart` an
in-memory database for tests).

Data lives in the `dice-dhamaal` Firebase project (Realtime Database,
anonymous sign-in), under `hisab/`, `hisabCodes/` and `hisabGc/`. The rules
are in `firebase/database.rules.json` and tested by `firebase/tests`.

The app currently signs in with the Video Player's Firebase app id. To give
it its own, register it once and pass the id at build time:

```
firebase apps:create ANDROID "Expense Tracker" --package-name in.onlysoftware.expense_tracker --project dice-dhamaal
flutter build apk --dart-define=FIREBASE_APP_ID=1:448997235311:android:...
```
