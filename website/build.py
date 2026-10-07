"""Builds the public website: one privacy policy page per app.

The apps link to https://dice-dhamaal.web.app/privacy/<app>.html (Firebase
Hosting, free). Edit the text here, then run from the repo root:

    python website/build.py
    cd website && firebase deploy --only hosting
"""

from html import escape
from pathlib import Path

PUBLIC = Path(__file__).resolve().parent / "public"
DEVELOPER = "Only Software"
UPDATED = "6 October 2026"

ADS = (
    "The app shows ads from Google AdMob. To show and measure ads, the Google "
    "Mobile Ads SDK collects your device's advertising ID, IP address, basic "
    "device information and how you interact with ads, and Google uses them as "
    "described in "
    '<a href="https://policies.google.com/technologies/partner-sites">How Google '
    "uses information from sites or apps that use its services</a>. In the "
    "European Economic Area, the UK and Switzerland the app asks for your consent "
    "first (Google's consent form), and you can change your choice any time in "
    "the app's settings under <b>Ad privacy choices</b>. You can reset or delete "
    "your advertising ID in Android Settings &gt; Privacy &gt; Ads."
)

FIREBASE = (
    "Online rooms use Google Firebase (Anonymous Authentication and Realtime "
    "Database). Firebase gives the app a random anonymous ID; it is not linked "
    "to your name, email or phone number. Data is sent encrypted (HTTPS). See "
    '<a href="https://firebase.google.com/support/privacy">Privacy and Security '
    "in Firebase</a>."
)

ON_DEVICE = (
    "Everything else you create in the app stays on your phone. We do not run "
    "our own servers and we never receive, sell or share it. Uninstalling the "
    "app or clearing its data in Android Settings deletes it."
)

APPS = {
    "qr_scanner": ("QR Scanner", [
        "The camera is used only while the scan screen is open, to read codes. "
        "Images are processed on your phone and are not saved or sent anywhere.",
        "Your scan history and the codes you create are stored only on your "
        "phone. You can delete them in the app.",
        "When you choose to open a link or call a number from a scanned code, "
        "the app hands it to your phone's browser or dialer.",
    ]),
    "daily_sudoku": ("Daily Sudoku", [
        "Your puzzles, progress, streak and settings are stored only on your "
        "phone.",
    ]),
    "doc_scanner": ("Doc Scanner", [
        "The camera is used only while you scan. Photos, scanned pages and PDFs "
        "are processed and stored on your phone; the app has no online upload.",
        "Files you open from your phone are read only to do what you asked "
        "(for example merge or compress a PDF). When you share a file, Android's "
        "share menu sends it to the app you pick.",
    ]),
    "expense_tracker": ("Expense Tracker", [
        "Your expenses, budgets and categories are stored only on your phone. "
        "CSV export creates a file only when you ask for it.",
        "Shared ledgers (the Friends tab) are stored online so both friends "
        "see the same list: the two names you type, each entry's amount, "
        "date, tag and note, who added or changed it and when, and the "
        "ledger's join code. Only phones that joined with the code can read "
        "a ledger. When both friends settle up, the ledger becomes read-only "
        "and is deleted automatically 14 days later. A friend can also leave "
        "a ledger, and an empty ledger can be deleted at any time. Ledgers "
        "use Google Firebase (Authentication and Realtime Database), which "
        "gives the app a random ID; data is sent encrypted (HTTPS). See "
        '<a href="https://firebase.google.com/support/privacy">Privacy and '
        "Security in Firebase</a>.",
        "Backup is optional. If you turn it on, Firebase Authentication "
        "stores your email address and password (hashed) together with the "
        "list of ledgers you are in, so a new phone can get them back. You can "
        "delete the account any time in the app (Friends tab &gt; cloud icon "
        "&gt; Delete account), which removes the email login and that list.",
    ]),
    "water_habit": ("Water Reminder", [
        "Your water log, habits, streaks and reminder times are stored only on "
        "your phone. Reminders are local notifications scheduled on the phone.",
    ]),
    "multi_speaker": ("Multi Speaker", [
        "Music is streamed directly between phones on the same Wi-Fi or hotspot. "
        "It never goes through the internet or our servers.",
        "Live mode uses Android's screen-capture permission to capture the "
        "sound other apps play (Android 10 and newer) so it can be sent to the "
        "other phones. That is why Android asks for the microphone and "
        "screen-capture permissions; the microphone itself is not recorded and "
        "nothing is saved.",
        "The camera is used only to scan another phone's QR code to join.",
    ]),
    "video_player": ("Video Player", [
        "The app reads the videos on your phone to list and play them. Videos "
        "are never uploaded. The private folder stays on your phone.",
        "Watch with friends on the same Wi-Fi streams the video directly from "
        "the host's phone to the friends' phones on that network.",
        "Online watch rooms (6-letter code) keep only what is needed to keep "
        "everyone in sync: the name you type for the room, the video's title or "
        "link, play "
        "and pause position, chat messages and reactions. Room data is deleted "
        "automatically within 12 hours. Only people with the room code can see "
        "it. " + FIREBASE,
        "The camera is used only to scan a room's QR code.",
    ]),
    "dice_dhamaal": ("Dice Dhamaal", [
        "Games against the computer and pass-and-play stay on your phone.",
        "Voice chat is off until you tap Voice during an online game. Only then "
        "does the app ask for microphone access. Calls go directly between the "
        "players' phones and are encrypted. Audio is never recorded or stored. "
        "To connect the phones, Google's public STUN servers see your IP "
        "address, and the other players' phones can see it too, as with any "
        "direct call.",
        "You can mute any player, which stops audio both ways, or report them. "
        "A report stores the room code, the reported player's display name and "
        "seat, the reason you picked, a random anonymous id for you, and the "
        "time. Reports are kept only until we review them.",
        "Online rooms (player names, moves and call set-up messages) live in "
        "Firebase Realtime Database and are deleted automatically within 6 "
        "hours. Only people with the room code can see them. " + FIREBASE,
    ]),
}

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  body {{ font: 16px/1.6 system-ui, sans-serif; max-width: 720px;
         margin: 0 auto; padding: 24px 16px; color: #1d1d1f; background: #fff; }}
  h1 {{ font-size: 1.6em; }} h2 {{ font-size: 1.15em; margin-top: 1.6em; }}
  a {{ color: #0b57d0; }} .muted {{ color: #666; }}
</style>
</head>
<body>
{body}
</body>
</html>
"""


def policy(name: str, facts: list[str]) -> str:
    items = "\n".join(f"<li>{f}</li>" for f in facts)
    return f"""<h1>{escape(name)} privacy policy</h1>
<p class="muted">{DEVELOPER} &middot; last updated {UPDATED}</p>
<p>{escape(name)} is a free Android app by {DEVELOPER}. This page explains what
data the app uses and why. No account is required and we do
not sell personal data.</p>
<h2>What the app does with your data</h2>
<ul>
{items}
</ul>
<p>{ON_DEVICE}</p>
<h2>Ads</h2>
<p>{ADS}</p>
<h2>Children</h2>
<p>The app is not made for children under 13 and we do not knowingly collect
data from them.</p>
<h2>Security and deletion</h2>
<p>Anything the app sends over the internet is encrypted in transit. Data on
your phone is deleted when you uninstall the app or clear its data. For data
held by Google for ads, use the controls above or
<a href="https://myadcenter.google.com/">My Ad Center</a>.</p>
<h2>Changes and contact</h2>
<p>If this policy changes, the new version is posted on this page with a new
date. Questions: write to the developer email shown on the app's Google Play
page.</p>
"""


def main() -> None:
    (PUBLIC / "privacy").mkdir(parents=True, exist_ok=True)
    links = []
    for app, (name, facts) in APPS.items():
        html = PAGE.format(title=f"{name} privacy policy", body=policy(name, facts))
        (PUBLIC / "privacy" / f"{app}.html").write_text(html, encoding="utf-8")
        links.append(f'<li><a href="privacy/{app}.html">{escape(name)}</a></li>')
    index = (
        f"<h1>{DEVELOPER}</h1>\n<p>Free Android apps.</p>\n"
        f"<h2>Privacy policies</h2>\n<ul>\n" + "\n".join(links) + "\n</ul>\n"
    )
    (PUBLIC / "index.html").write_text(
        PAGE.format(title=DEVELOPER, body=index), encoding="utf-8")


if __name__ == "__main__":
    main()
