# PDF to Word Converter — Web App

A browser-based **PDF → .docx** converter built on top of [OpenDataLoader PDF](https://github.com/opendataloader-project/opendataloader-pdf).

## Architecture

```
                    Browser (GitHub Pages)
                   ┌───────────────────────┐
  User uploads PDF │  web/index.html       │
  ────────────────>│                       │
                   │  1. POST file to      │
                   │     parser service    │
                   │         │             │
                   └─────────┼─────────────┘
                             │ multipart/form-data
                             ▼
              Remote Parser Service (Python)
             ┌────────────────────────────────┐
             │  web/parser-server/app.py      │
             │  (FastAPI + opendataloader-pdf)│
             │                                │
             │  opendataloader_pdf.convert()  │
             │  format="html,markdown"        │
             └──────────────┬─────────────────┘
                            │ JSON { html, markdown }
                            ▼
                   Browser (GitHub Pages)
                  ┌──────────────────────────┐
                  │  2. Receive parser output │
                  │                           │
                  │  3a. If HTML available:   │
                  │      feed into html-docx  │
                  │                           │
                  │  3b. Else: render via     │
                  │      markdown-it → HTML   │
                  │      then html-docx       │
                  │                           │
                  │  4. Download .docx        │
                  └──────────────────────────┘
```

## Why HTML first, Markdown fallback?

- **HTML** is richer: preserves table structure, inline styles, image layout.
  `html-docx-js` ingests it directly → higher fidelity .docx.
- **Markdown** is cleaner text: OpenDataLoader produces excellent structured
  Markdown (headings, lists, tables).  `markdown-it` renders it to HTML which
  is then fed to `html-docx-js` as a fallback when the HTML output is absent
  or deliberately preferred.

## Files

| File | Purpose |
|------|---------|
| `web/index.html` | Single-page GitHub Pages UI — PDF upload, convert, download |
| `web/parser-server/app.py` | FastAPI reference server — calls `opendataloader_pdf.convert()` |
| `web/parser-server/requirements.txt` | Python dependencies for the parser server |

## Quick Start

### 1. Enable GitHub Pages

In your fork, go to **Settings → Pages** and set the source to
**Deploy from a branch → main / web**.  Your UI will be live at
`https://<you>.github.io/opendataloader-pdf/`.

### 2. Deploy the parser server

The simplest way for local or cloud deployment:

```bash
# Install Python dependencies (Java 11+ must also be in PATH)
pip install -r web/parser-server/requirements.txt

# Start the server
uvicorn web.parser-server.app:app --host 0.0.0.0 --port 8000

# For hybrid mode (better table/OCR accuracy):
opendataloader-pdf-hybrid --port 5002 &
HYBRID=docling-fast uvicorn web.parser-server.app:app --host 0.0.0.0 --port 8000
```

Then enter `http://localhost:8000/convert` as the Parser service URL in the UI.

### 3. Using the UI

1. Open the GitHub Pages URL.
2. Enter the parser service URL.
3. Drag-and-drop or click to upload a PDF.
4. (Optional) choose HTML or Markdown as the intermediate format.
5. Click **Convert & Download .docx**.

## No server? No problem.

Run OpenDataLoader locally and paste its output:

```bash
opendataloader-pdf your-doc.pdf --format html,markdown
# Generates: your-doc.html  your-doc.md
```

Open the `.html` or `.md` output, select all, copy, and paste it into the
**"Or paste Markdown / HTML directly"** text area in the UI.

## Browser libraries (CDN)

| Library | Version | Purpose |
|---------|---------|---------|
| [html-docx-js](https://github.com/evidenceprime/html-docx-js) | 0.3.1 | Convert HTML string → .docx Blob in the browser |
| [markdown-it](https://github.com/markdown-it/markdown-it) | 14 | Render Markdown → HTML (fallback path) |

Both are loaded lazily from jsDelivr CDN only when needed — no build step required.

## CORS

The parser server includes permissive CORS headers by default (`allow_origins=["*"]`).
For production, restrict to your GitHub Pages origin in `app.py`:

```python
allow_origins=["https://yourusername.github.io"],
```

## License

Apache 2.0 — same as the parent project.
