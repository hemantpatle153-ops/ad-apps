# Firebase setup for Dice Dhamaal online rooms

One-time setup, about ten minutes. Everything offline works without it.

1. Open <https://console.firebase.google.com> and sign in with the Google
   account you use for Play. Click **Create a project**, name it
   `dice-dhamaal`, and turn Google Analytics off (not needed).
2. In the project, open **Build > Authentication > Get started**, pick
   **Anonymous** in the Sign-in method list and enable it. Players never see
   a login; this is only so the server can tell phones apart.
3. Open **Build > Realtime Database > Create database**. Pick the region
   closest to your players (`asia-southeast1` for India) and start in
   **locked mode**.
4. Open the **Rules** tab, replace everything with the rules at the bottom of
   this file and click **Publish**.
5. Open **Project settings** (gear icon) **> General**, scroll to "Your apps"
   and click the Android icon. Package name: `in.onlysoftware.dice_dhamaal`.
   Download of `google-services.json` is **not** needed; the app reads its
   settings from the build command instead.
6. Still in Project settings, copy these four values and the database URL from
   the Realtime Database page:

   | Build flag | Where to find it |
   | --- | --- |
   | `FIREBASE_API_KEY` | Project settings > General > Web API Key |
   | `FIREBASE_APP_ID` | Project settings > Your apps > App ID (`1:...:android:...`) |
   | `FIREBASE_PROJECT_ID` | Project settings > General > Project ID |
   | `FIREBASE_SENDER_ID` | Project settings > Cloud Messaging > Sender ID |
   | `FIREBASE_DB_URL` | Realtime Database > the `https://...firebasedatabase.app` link |

7. The app has these values built in for the `dice-dhamaal` project (see
   `FirebaseSetup` in `lib/ludo/online/firebase_backend.dart`), so a plain
   `flutter build apk` has online rooms. To point a build at another
   project, pass the five values with `--dart-define=NAME=value`.

The free Spark plan covers this: rooms hold a few kilobytes each and are
deleted by the rules below once they are a day old.

## Database rules

The rules also live in `firebase/database.rules.json`; deploy them from
that folder with `firebase deploy --only database`.

A player may read a room and write only their own seat and the next move. The
`.validate` on `size` keeps a room from being rewritten once it exists.

```json
{
  "rules": {
    "rooms": {
      ".indexOn": [
        "created"
      ],
      ".read": "auth != null && query.orderByChild == 'created' && query.limitToFirst <= 20",
      "$code": {
        ".write": "auth != null && !newData.exists() && data.child('created').val() < now - 21600000",
        ".read": "auth != null",
        "size": {
          ".write": "auth != null && !data.exists()",
          ".validate": "newData.isNumber() && newData.val() >= 2 && newData.val() <= 4"
        },
        "rules": {
          ".write": "auth != null && !data.exists()"
        },
        "created": {
          ".write": "auth != null && !data.exists()",
          ".validate": "newData.val() == now"
        },
        "started": {
          ".write": "auth != null && newData.parent().child('members/'+auth.uid).exists()",
          ".validate": "newData.isBoolean()"
        },
        "members": {
          "$uid": {
            ".write": "auth != null && $uid == auth.uid"
          }
        },
        "seats": {
          "$seat": {
            ".write": "auth != null && (!data.exists() || data.child('uid').val() == auth.uid)",
            ".validate": "newData.child('uid').val() == auth.uid || !newData.exists()"
          }
        },
        "actions": {
          "$index": {
            ".write": "auth != null && !data.exists() && root.child('rooms/'+$code+'/members/'+auth.uid).exists()"
          }
        },
        "signal": {
          "$seat": {
            "$id": {
              ".write": "auth != null && root.child('rooms/'+$code+'/members/'+auth.uid).exists()"
            }
          }
        }
      }
    }
  }
}
```

## Staying on the free plan

The project is on the free Spark plan, which has no billing account, so it
can never be charged; if a limit is reached, online rooms stop working until
the next day or month instead. The limits that matter: 1 GB stored, 10 GB
downloaded a month and 100 phones connected at once.

To keep storage small without a paid server job, rooms delete themselves:
every time someone creates a room, the app deletes up to 20 rooms older than
6 hours (the rules let a signed-in phone list the oldest rooms 20 at a time, and
delete a room only once it is that old, checked with the server's clock). Voice-call messages are deleted as
soon as they are read.
