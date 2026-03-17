# PDF to Word Converter — Local App

A **zero-configuration, one-click** PDF → .docx converter that runs entirely
on your machine. No cloud, no subscriptions, no data leaving your computer.

## What you get

| File | Purpose |
|------|---------|
| `install-and-run.bat` | **Windows** double-click launcher |
| `install-and-run.sh` | **Mac / Linux** launcher |
| `index.html` | The browser UI (opened automatically) |

## How to download

**Download the whole folder as a ZIP:**

1. Go to the repository root: https://github.com/professorgeorge/opendataloader-pdf
2. Click the green **Code** button → **Download ZIP**
3. Extract the ZIP
4. Open the `local-app/` folder

Or download just this folder with a tool like `git sparse-checkout`:
```bash
git clone --filter=blob:none --sparse https://github.com/professorgeorge/opendataloader-pdf.git
cd opendataloader-pdf
git sparse-checkout set local-app
```

## How to run

### Windows

1. Open the `local-app` folder
2. Double-click **`install-and-run.bat`**
3. On first run it will:
   - Download and install **Java 21** if not already installed (~50 MB, one-time)
   - Download and install **Python 3.12** if not already installed (~25 MB, one-time)
   - Install the required Python packages (~100 MB, one-time)
4. Your browser opens automatically to **http://localhost:8000**
5. Upload a PDF → click **Convert & Download .docx**

> **Note:** If asked by Windows Defender / SmartScreen, click "More info" → "Run anyway".
> The script only downloads official installers from adoptium.net and python.org.

### macOS

1. Open Terminal in the `local-app` folder
2. Run:
   ```bash
   bash install-and-run.sh
   ```
3. On first run it installs Java and Python via **Homebrew** (installed automatically if needed)
4. Browser opens to **http://localhost:8000**

### Linux (Ubuntu / Debian / Fedora / Arch)

```bash
bash install-and-run.sh
```

Uses `apt-get`, `dnf`, or `pacman` to install Java and Python if missing.
May ask for your `sudo` password on first run.

## What happens on each run

```
[1/4] Check / install Java    (OpenDataLoader parser needs the JVM)
[2/4] Check / install Python  (runs the FastAPI server)
[3/4] Install Python packages (opendataloader-pdf, fastapi, uvicorn)
[4/4] Start server + open browser at http://localhost:8000
```

Steps 1-3 are **skipped on subsequent runs** if already installed.
Cold start after first install: ~3 seconds.

## How conversion works

```
Your PDF
   |
   v  (POST to http://localhost:8000/convert)
Local Python server  (web/parser-server logic embedded in the launcher)
   |
   v  opendataloader_pdf.convert(format="html,markdown", image_output="embedded")
HTML + Markdown output
   |
   v  (returned as JSON)
Your browser
   |
   +-- if HTML available:   html-docx-js.asBlob(html)  -> download .docx
   +-- else:                markdown-it.render(md) -> html-docx-js -> .docx
```

## Stopping the server

- **Windows:** Close the **"OpenDataLoader PDF Server"** console window,
  or press `Ctrl+C` in that window.
- **Mac/Linux:** Press `Ctrl+C` in the terminal where you ran the script.

## Requirements (auto-installed)

| Component | Version | Auto-installed? |
|-----------|---------|-----------------|
| Java (JRE) | 11+ | Yes (Adoptium 21) |
| Python | 3.10+ | Yes (Python 3.12) |
| opendataloader-pdf | latest | Yes (pip) |
| fastapi + uvicorn | latest | Yes (pip) |

## Privacy

- **100% local** — no data is sent anywhere.
- The server only listens on `127.0.0.1` (localhost), not reachable from other machines.
- DOCX conversion happens in your browser tab.

## License

Apache 2.0
