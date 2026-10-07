# Doc Scanner - Play Console sheet

- Folder: `apps/doc_scanner` - Package: `in.onlysoftware.doc_scanner`
- Type: App - Free - Contains ads - Ages 13+
- Privacy policy: https://dice-dhamaal.web.app/privacy/doc_scanner.html

What the code really does: in-app camera scanner with automatic edge finding and auto capture (up to 50 pages, 100 in "Book" mode), crop, rotate, 7 filters (Original, Magic color, Clean B&W, Auto color, Grayscale, Whiteboard, B&W), page size choice, save as multi-page PDF; optional on-device text recognition (Google ML Kit, Latin script only) to make PDFs searchable; ID card (both sides on one page); business card to contact file (.vcf, shared via Android share); import photos (system photo picker) and PDFs; "Open with" / "Share to" from other apps; search names and text inside documents; viewer with print/share/save to a folder the user picks. PDF tools: merge, split, organize pages, rotate, compress, repair, OCR PDF, PDF to JPG, JPG to PDF, PDF to Word (.docx), Word to PDF (text only), extract text, sign, add text, watermark, page numbers, crop, redact (pages become images so hidden text is really removed), protect with password (AES-256), unlock, compare two documents. All processing on the phone; no upload.

## 1. Store listing

**App name** (22/30)
```
Doc Scanner: PDF & OCR
```

**Short description** (74/80)
```
Scan pages to clean PDFs, read text with OCR and edit, sign or merge PDFs.
```

**Full description** (1865/4000)
```
Turn paper into neat PDF files with your phone camera. Doc Scanner finds the page edges, takes the picture for you and cleans up shadows. Everything is done on your phone; your documents are not uploaded.

SCAN
- Automatic edge detection and auto capture, or take the photo yourself.
- Crop, rotate and reorder pages before saving.
- 7 looks: Original, Magic color, Clean B&W, Auto color, Grayscale, Whiteboard and B&W.
- Many pages in one PDF, and a Book mode for long notes.
- ID card mode puts the front and back on one page.
- Business card mode reads the name, phone and email and makes a contact file you can share.
- Import photos from your gallery or PDFs from your files.

TEXT RECOGNITION (OCR)
Turn on "Recognize text" when you save and the PDF becomes searchable and its text can be copied. Search finds words inside all your documents. Text recognition works on the phone and supports Latin-script languages such as English.

PDF TOOLS
- Organize: merge, split, reorder, rotate and delete pages, crop page edges.
- Optimize: compress to a smaller file, repair a damaged file, add OCR to an old scan.
- Convert: PDF to JPG, JPG to PDF, PDF to Word (.docx), Word text to PDF, extract all text.
- Edit: draw and place your signature, add text, watermark, page numbers.
- Security: redact private details (the hidden text is really removed), protect a PDF with a password, remove a password you know.
- Compare two documents and see what changed.

SHARE AND SAVE
Share PDFs to any app, print them, save a copy to a folder you choose, or open them in another PDF app. You can also open or share PDFs and photos from other apps straight into Doc Scanner.

PRIVATE BY DESIGN
No account, no cloud. Your files stay in the app's storage on your phone until you share or save them. The app shows ads from Google AdMob; EU and UK users are asked for consent first.
```

**Category:** Productivity
**Tags:** Document scanner, PDF, Scanner, Productivity, Office

## 2. Data safety

Scanned pages, PDFs, OCR text and signatures stay on the phone = **not collected**. Sharing a file through Android's share menu is a user action to an app they pick = not "shared" by you.

| Data type | Collected | Shared | Ephemeral | Required / Optional | Purposes | Source |
|---|---|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob (IP address) |
| App activity > App interactions | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob |
| App info and performance > Crash logs, Diagnostics | Yes | Yes | No | Required | Analytics, Fraud prevention/security | AdMob SDK; ML Kit text recognition sends usage/performance metrics to Google |
| Device or other IDs | Yes | Yes | No | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID, app set ID; ML Kit install ID |
| Photos and videos, Files and docs, Personal info, Contacts, Financial info, Audio, Messages | No | No | - | - | - | Processed and stored only on the phone |

- Encrypted in transit: **Yes**.
- Deletion request: **No** (no account; users delete documents in the app or uninstall).

## 3. Permissions and declarations

| Permission | Why (paste text) | Play form? |
|---|---|---|
| CAMERA | "The camera is used only while you scan a document, ID card or business card. Pictures are processed on the phone and saved only as your PDF." | No form. The app already shows a clear message and a Settings button when camera access is off (`lib/scan/camera_scan_screen.dart:663-687`). |
| INTERNET | Ads only. | No |
| AD_ID (AdMob SDK) | Advertising ID: **Yes** - Advertising, Analytics, Fraud prevention. | Advertising ID form |
| Photos: none | Photo import uses Android's photo picker (`image_picker`) and file picker, saving uses the system "save as" dialog. No READ_MEDIA_* or storage permission is needed, so **no Photo & Video permissions declaration**. | - |

Check **App bundle explorer > Permissions** after upload: if `RECORD_AUDIO` appears, see risk 1.

## 4. Content rating (IARC)

- Category: **Utility, Productivity, Communication or Other**.
- All content questions (violence, sexuality, language, drugs, gambling): **No**.
- Users interact with each other: **No**. Shares location: **No**. Digital purchases: **No**. Web browsing: **No**.
- Expected: Everyone / PEGI 3 / IARC 3+.

## 5. Ads, audience and other declarations

- Contains ads: **Yes** - banner, interstitial only after a PDF is saved (2-minute gap).
- Target audience: **13-15, 16-17, 18+**. Appeals to children: No.
- Financial: none. Health: none. Government: **No** (ID card mode only scans the user's own card; it is not a government service - don't use any government logo or "Aadhaar/PAN official" words in the listing). News: No.

## 6. Policy risks found in the code

| # | Risk | Where | What to do |
|---|---|---|---|
| 1 | The `camera` plugin (Android CameraX) declares **RECORD_AUDIO** in its own manifest for video recording. If it lands in the merged manifest, Play shows "Microphone" on your listing and reviewers may ask why a scanner records audio. The app never records audio. | `apps/doc_scanner/pubspec.yaml` (`camera: ^0.12.1`), `apps/doc_scanner/android/app/src/main/AndroidManifest.xml:1-7` (no removal rule) | Check App bundle explorer. If present, add to the app manifest: `<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>` (with `xmlns:tools`). |
| 2 | Name mismatch: launcher "Doc Scanner", in-app title "Document Scanner". | `apps/doc_scanner/android/app/src/main/AndroidManifest.xml:9`, `apps/doc_scanner/lib/main.dart:36` | Fine, but keep store name starting with "Doc Scanner". |
| 3 | OCR is Latin script only (`TextRecognitionScript.latin`). | `apps/doc_scanner/lib/ocr.dart:16` | Do not claim Hindi or other Indian-script OCR in the listing (the text above is correct). |
| 4 | "Unlock PDF" removes a password. It asks for the right password first, so it is not a cracking tool. | `apps/doc_scanner/lib/pdf_tools.dart:251-255` | Keep the listing wording "remove a password you know". |
