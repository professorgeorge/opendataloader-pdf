"""
web/parser-server/app.py

Reference FastAPI server: bridges the browser UI (web/index.html) to the
OpenDataLoader PDF parser.  The browser POSTs a PDF file here; this server
runs opendataloader_pdf.convert() and returns { html, markdown } JSON.

Usage:
  pip install fastapi uvicorn python-multipart opendataloader-pdf
  uvicorn app:app --host 0.0.0.0 --port 8000

For hybrid / OCR mode, also start the hybrid backend first:
  opendataloader-pdf-hybrid --port 5002
Then set HYBRID=docling-fast in the environment before starting uvicorn.

Endpoints:
  POST /convert   multipart/form-data  { file: <PDF binary>, format?: string }
  GET  /health    { status: "ok" }
"""

import os
import tempfile
import glob
from pathlib import Path

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import opendataloader_pdf

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = FastAPI(
    title="OpenDataLoader PDF Parser Service",
    description="Bridge between the browser PDF-to-DOCX UI and OpenDataLoader.",
    version="1.0.0",
)

# Allow the GitHub Pages UI (and localhost dev) to call this server.
# In production, restrict origins to your actual GitHub Pages domain.
ALLOWED_ORIGINS = os.environ.get(
    "CORS_ORIGINS",
    "http://localhost:*,https://*.github.io,https://*.github.com",
).split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten in production
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Optional hybrid mode (set HYBRID=docling-fast to enable)
# ---------------------------------------------------------------------------
HYBRID = os.environ.get("HYBRID", "off")  # "off" | "docling-fast"


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/health")
def health():
    return {"status": "ok", "hybrid": HYBRID}


# ---------------------------------------------------------------------------
# /convert  -- main endpoint
# ---------------------------------------------------------------------------
@app.post("/convert")
async def convert(
    file:   UploadFile = File(..., description="PDF file to convert"),
    format: str        = Form("html,markdown", description="Comma-separated output formats"),
) -> JSONResponse:
    """
    1. Save the uploaded PDF to a temp directory.
    2. Run opendataloader_pdf.convert() requesting HTML and Markdown output.
    3. Read the generated files and return { html, markdown } JSON.
    4. Clean up temp files.
    """
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only .pdf files are supported.")

    # Normalise requested formats
    requested_formats = {f.strip().lower() for f in format.split(",")}
    # Always request both so the browser can choose; filter later if needed
    output_formats = "html,markdown"

    with tempfile.TemporaryDirectory() as tmpdir:
        pdf_path = Path(tmpdir) / file.filename

        # Write uploaded PDF to disk
        content = await file.read()
        pdf_path.write_bytes(content)

        # Run the converter
        convert_kwargs = dict(
            input_path=[str(pdf_path)],
            output_dir=tmpdir,
            format=output_formats,
            image_output="embedded",  # Base64 images inline -- portable for DOCX
            quiet=True,
        )
        if HYBRID != "off":
            convert_kwargs["hybrid"] = HYBRID

        try:
            opendataloader_pdf.convert(**convert_kwargs)
        except Exception as exc:
            raise HTTPException(
                status_code=500,
                detail=f"Parser error: {exc}",
            ) from exc

        # Collect output files
        stem  = pdf_path.stem
        html_files = glob.glob(f"{tmpdir}/{stem}*.html")
        md_files   = glob.glob(f"{tmpdir}/{stem}*.md")

        html_content = Path(html_files[0]).read_text("utf-8") if html_files else ""
        md_content   = Path(md_files[0]).read_text("utf-8")   if md_files   else ""

    return JSONResponse({
        "html":     html_content,
        "markdown": md_content,
        "filename": file.filename,
        "formats":  list(requested_formats),
    })


# ---------------------------------------------------------------------------
# Dev entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8000)))
