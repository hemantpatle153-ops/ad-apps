# Firebase project `dice-dhamaal`

Shared by the apps that need a server. Each app keeps its data under its own
top-level path in Realtime Database (Dice Dhamaal uses `rooms/`), and adds its
section to `database.rules.json` here instead of replacing the file.

Deploy the rules from this folder:

```
firebase deploy --only database
```
