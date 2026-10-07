# Expense Tracker - Play Console sheet

- Folder: `apps/expense_tracker` - Package: `in.onlysoftware.expense_tracker`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/expense_tracker.html

What the code really does: add, edit and delete expenses (amount, one of 12 categories, optional note, date); month view grouped by day with day totals, "spent this month" and "today"; optional monthly budget with progress bar and "over budget" warning; Insights tab with a category donut chart, per-day bar chart and average per day; move between months; choose a currency symbol (10 options); export all expenses as a CSV file through the Android share menu. Data is in a SQLite database on the phone. No bank link, no SMS reading, no income tracking, no cloud backup.

## 1. Store listing

**App name** (29/30)
```
Expense Tracker: Daily Budget
```

**Short description** (77/80)
```
Log daily spending in seconds, set a monthly budget and see where money goes.
```

**Full description** (1355/4000)
```
A simple, offline expense tracker. Write down what you spend in a few taps and see your month at a glance.

QUICK ENTRY
Tap "Add expense", type the amount, pick a category and save. Add a note and change the date if you like. Tap any entry later to edit or delete it.

12 CATEGORIES
Food, Groceries, Transport, Fuel, Shopping, Bills, Rent, Health, Education, Entertainment, Gifts and Other, each with its own icon and color.

YOUR MONTH
- Total spent this month and today.
- Expenses grouped by day, with a total for each day.
- Go back to earlier months any time.

MONTHLY BUDGET
Set a budget and watch the bar fill up. The app shows how much is left, or how much you are over.

INSIGHTS
- A donut chart of spending by category, with amounts and percentages.
- A bar chart of spending per day of the month.
- Your average spend per day.

EXPORT
Export every expense as a CSV file and open it in a spreadsheet app, or keep it as a backup. The file is shared only when you choose to.

YOUR CURRENCY
Choose a currency symbol: ₹, $, €, £, ¥, Rs, R$, ₦, ₱ or ৳.

PRIVATE AND OFFLINE
Your expenses are stored only on your phone. No sign-up, no bank login, no SMS reading. The app shows ads from Google AdMob; EU and UK users are asked for consent first.

This app is a personal record-keeping tool. It does not give loans, financial advice or payment services.
```

**Category:** Finance
**Tags:** Expense tracker, Budget, Money manager, Personal finance, Spending

## 2. Data safety

Expenses, notes, budget and currency stay in the phone's database = **not collected**. The CSV export is sent only by the user through the share menu = not collected/shared by the app.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID |
| Financial info (purchase history, other financial info) | **No** | No | - | - | - | Stays on the phone |
| All other types | No | No | - | - | - | - |

- Encrypted in transit: **Yes**.
- Deletion request: **No** (no account; users delete entries in the app or uninstall).

## 3. Permissions and declarations

| Permission | Why | Play form? |
|---|---|---|
| INTERNET | Ads only. | No |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |

No SMS, contacts, storage or location permission. (Good: SMS permissions for expense apps are heavily restricted on Play.)

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other**.
- All content questions: **No**. Gambling: **No**.
- Users interact: **No**. Shares location: **No**. Digital purchases: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner; interstitial after every 3rd saved expense, at most once every 2 minutes.
- Target audience: **13-15, 16-17, 18+**.
- **Financial features declaration: "My app doesn't provide any financial features."** Reason (keep for a reviewer): the app only stores numbers the user types, on the phone. It does not offer banking, loans, payments, money transfer, investing, insurance, crypto or credit, and does not connect to any account. The Finance *category* is fine for a budgeting tool; the financial *features* form is about financial services.
- Personal loan rules: not applicable (no loans).
- Health: none. Government: No. News: No.

## 6. Policy risks found in the code

| Risk | Where | What to do |
|---|---|---|
| Interstitial right after saving (every 3rd save). Saving is a natural break, and the 2-minute cooldown in `app_core` limits it, but users logging many expenses may still see "ad after tap Save". | `apps/expense_tracker/lib/main.dart:72-75` | OK for AdMob policy. If reviews complain, raise to every 5th save. |
| Name mismatch: launcher "Expense Tracker", in-app title "Daily Expense Tracker". | `apps/expense_tracker/android/app/src/main/AndroidManifest.xml:4`, `apps/expense_tracker/lib/main.dart:31` | Not a violation. Keep "Expense Tracker" at the start of the store name. |
| Listing must not promise things the app does not do (bank sync, SMS auto-tracking, cloud backup, income, reports PDF). | - | The text above avoids them. |
