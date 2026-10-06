# Doc Scanner

Scan documents to searchable PDFs and work with PDFs, all on the phone.
No server: nothing is uploaded.

**Scan (Adobe Scan style):** document scanner with auto edge detection,
crop and cleanup (Google ML Kit), plain camera photos, ID card (both sides
at real size on one A4 page), business card (reads name, phone, email,
website and saves a contact), book/notes mode, gallery import, PDF import.
Per-page filters (auto color, grayscale, whiteboard, B&W) and rotation.
On-device OCR adds a hidden text layer, so PDFs are searchable and the
document list can be searched by the text inside them. Save as PDF or JPG.

**Tools (iLovePDF style):** merge, split, organize pages (reorder, rotate,
duplicate, delete), rotate, compress (lossless or strong), repair, OCR PDF,
PDF to JPG, JPG to PDF, PDF to Word (text), Word to PDF (text), extract
text, sign (draw and place), add text, watermark, page numbers, crop,
redact (pages are flattened so hidden text is really gone), protect
(AES-256) and unlock, and compare two documents (PDFs, scans or photos;
word-level changes plus pages side by side).

Not offline: full-fidelity Office conversions (layout, tables, images),
PDF to Excel/PowerPoint, HTML to PDF, translation and AI summaries need a
server and are left out.

PDF editing uses `syncfusion_flutter_pdf`, which needs Syncfusion's free
Community License (companies under $1M revenue, up to 5 developers).

See the repository README for build and release steps.
