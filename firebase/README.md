# Firebase project `dice-dhamaal`

Shared by the apps that need a server. Each app keeps its data under its own
top-level path in Realtime Database, and adds its section to
`database.rules.json` here instead of replacing the file:

- `rooms/`: Dice Dhamaal online Ludo.
- `watch/`: Video Player watch parties.
- `hisab/`, `hisabCodes/`, `hisabGc/`: Expense Tracker's shared hisab with
  friends. Cleared logs are deleted 14 days after both friends confirm.

Deploy the rules from this folder:

```
firebase deploy --only database
```

Test the rules on the local emulator (needs Java and Node):

```
cd tests && npm ci && npm test
```
