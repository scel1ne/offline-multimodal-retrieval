# Celine Retrieval — Web Companion

A self-contained, **offline-first** browser build of the Celine Retrieval
desktop app. Open `index.html` in any modern browser (Chrome, Safari,
Edge, Firefox) and the entire app runs locally — your files never leave
the browser.

## Features

- **Drag & drop ingestion** for `.txt`, `.md`, `.csv`, `.json`, `.html`,
  `.xml`, `.pdf`, `.docx`, and common image formats
- **Local PDF parsing** via PDF.js (loaded on demand from CDN the first
  time you index a PDF; cached afterwards)
- **Inline DOCX parsing** using a built-in ZIP/deflate reader — no
  third-party libraries required
- **Hybrid scoring** combining keyword matching, cosine similarity, and
  filename boosting — same algorithm as the Flutter desktop build
- **Per-document occurrence pager**: every match of the query inside a
  single file is highlighted and can be stepped through with previous
  / next buttons, with progress indicators and position info
- **Light, dark, and high-contrast themes** with adjustable text scaling
- **Export / import** the index as JSON for cross-device sync
- **Zero build step** — just open the file

## Run

```bash
# macOS
open index.html

# Linux / generic
xdg-open index.html

# Or serve over HTTP (recommended for some browsers' file:// restrictions)
python3 -m http.server 8000
# then visit http://localhost:8000
```

## Browser support

Modern evergreen browsers. Uses `DecompressionStream` for inline DOCX
support, so anything released in the last few years works fine.

## Privacy

- No analytics, no tracking, no network calls except the one-time PDF.js
  CDN fetch (and only if you actually index a PDF).
- All file content stays in memory inside this browser tab.
- Use the **Export** button to save your index as a JSON file, then
  **Import** it on another machine or browser.
