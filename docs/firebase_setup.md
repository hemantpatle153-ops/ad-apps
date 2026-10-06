# Firebase setup for Dice Dhamaal online rooms

One-time setup, about ten minutes. Everything offline works without it.

1. Open <https://console.firebase.google.com> and sign in with the Google
   account you use for Play. Click **Create a project**, name it
   `ludo-party`, and turn Google Analytics off (not needed).
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

7. Build with them:

```
flutter build appbundle \
  --dart-define=FIREBASE_API_KEY=AIza... \
  --dart-define=FIREBASE_APP_ID=1:123456789:android:abcdef \
  --dart-define=FIREBASE_PROJECT_ID=ludo-party \
  --dart-define=FIREBASE_SENDER_ID=123456789 \
  --dart-define=FIREBASE_DB_URL=https://ludo-party-default-rtdb.asia-southeast1.firebasedatabase.app
```

The free Spark plan covers this: rooms hold a few kilobytes each and are
deleted by the rules below once they are a day old.

## Database rules

A player may read a room and write only their own seat and the next move. The
`.validate` on `size` keeps a room from being rewritten once it exists.

```json
{
  "rules": {
    "rooms": {
      "$code": {
        ".read": "auth != null",
        "size": {
          ".write": "auth != null && !data.exists()",
          ".validate": "newData.isNumber() && newData.val() >= 2 && newData.val() <= 4"
        },
        "rules": { ".write": "auth != null && !data.exists()" },
        "created": {
          ".write": "auth != null && !data.exists()",
          ".validate": "newData.val() == now"
        },
        "started": {
          ".write": "auth != null && root.child('rooms/'+$code+'/members/'+auth.uid).exists()",
          ".validate": "newData.isBoolean()"
        },
        "members": {
          "$uid": { ".write": "auth != null && $uid == auth.uid" }
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

Old rooms are not deleted automatically by these rules. Once a month, open
Realtime Database > Data and delete the `rooms` node, or add a scheduled
Cloud Function if that becomes a chore.
