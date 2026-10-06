# Expense Tracker

Offline daily expense tracker with budget, insights and CSV export, plus
**Friends**: shared money ledgers with friends.

See the repository README for build and release steps.

## Shared ledgers with friends

The Friends tab keeps track of money lent and borrowed between two friends.

- **Start a shared ledger** with your name and your friend's. You get an 8 letter code
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
- **Settle up**: one friend confirms the final amount, the other confirms the
  same amount, and the ledger is settled. Any change in between cancels the
  confirmations. A settled ledger is read-only for 14 days (it can be reopened,
  with a new code), then deleted from Firebase. Each phone keeps its own copy.

- **Getting ledgers back**: after a reinstall or on a new phone, join again
  with the code and pick your own name; your entries are tied to your side,
  not to the phone. Or turn on the optional **email backup** (cloud icon on
  the Friends tab): signing in with the same email brings back every ledger.

Code: `lib/ledger/` (`model.dart` holds the math and every database write;
`service.dart` the flows; `backend.dart` Firebase; `memory_backend.dart` an
in-memory database for tests).

Data lives in the `dice-dhamaal` Firebase project (Realtime Database,
anonymous sign-in), under `ledger/`, `ledgerCodes/`, `ledgerGc/` and `ledgerUsers/` (each
account's list of ledgers). Email backup needs the Email/Password sign-in
provider turned on in Firebase Authentication. The rules
are in `firebase/database.rules.json` and tested by `firebase/tests`.

The app currently signs in with the Video Player's Firebase app id. To give
it its own, register it once and pass the id at build time:

```
firebase apps:create ANDROID "Expense Tracker" --package-name in.onlysoftware.expense_tracker --project dice-dhamaal
flutter build apk --dart-define=FIREBASE_APP_ID=1:448997235311:android:...
```
