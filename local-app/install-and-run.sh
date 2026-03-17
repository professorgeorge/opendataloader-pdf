#!/usr/bin/env bash
# =============================================================
#  PDF to Word Converter - One-click local installer/launcher
#  Works on macOS and Linux (Ubuntu/Debian/Fedora/Arch)
#  Usage: bash install-and-run.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8000

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo "============================================================"
echo "  PDF to Word Converter  |  Powered by OpenDataLoader"
echo "============================================================"
echo

# -------------------------------------------------------------
# STEP 1 - Java
# -------------------------------------------------------------
info "[1/4] Checking for Java..."
if ! command -v java &>/dev/null; then
    warn "Java not found. Installing Java 21 JRE..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use Homebrew
        if ! command -v brew &>/dev/null; then
            info "Installing Homebrew first..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install --cask temurin@21 || brew install openjdk@21
    elif command -v apt-get &>/dev/null; then
        # Debian / Ubuntu
        sudo apt-get update -qq
        sudo apt-get install -y -qq default-jre-headless
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL
        sudo dnf install -y java-21-openjdk-headless
    elif command -v pacman &>/dev/null; then
        # Arch
        sudo pacman -Sy --noconfirm jre-openjdk-headless
    else
        error "Cannot auto-install Java on this system. Please install Java 11+ from https://adoptium.net then re-run this script."
    fi
    command -v java &>/dev/null || error "Java install failed. Install manually from https://adoptium.net"
    info "Java installed."
else
    info "Java found. OK."
fi
echo

# -------------------------------------------------------------
# STEP 2 - Python 3
# -------------------------------------------------------------
info "[2/4] Checking for Python 3..."
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        VER=$("$cmd" -c "import sys; print(sys.version_info.major)")
        if [[ "$VER" == "3" ]]; then
            PYTHON="$cmd"
            break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    warn "Python 3 not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install python3
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y -qq python3 python3-pip
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y python3 python3-pip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm python python-pip
    else
        error "Cannot auto-install Python on this system. Please install Python 3.10+ from https://python.org then re-run this script."
    fi
    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null; then PYTHON="$cmd"; break; fi
    done
    [[ -n "$PYTHON" ]] || error "Python install failed. Install manually from https://python.org"
    info "Python installed."
else
    info "Python found: $($PYTHON --version). OK."
fi
echo

# -------------------------------------------------------------
# STEP 3 - Python packages
# -------------------------------------------------------------
info "[3/4] Installing required packages (first run: ~1-2 min)..."
"$PYTHON" -m pip install --quiet --upgrade pip
"$PYTHON" -m pip install --quiet opendataloader-pdf fastapi "uvicorn[standard]" python-multipart
info "Packages ready."
echo

# -------------------------------------------------------------
# STEP 4 - Write embedded server + launch
# -------------------------------------------------------------
info "[4/4] Starting PDF converter at http://localhost:${PORT} ..."

SERVER_PY="${SCRIPT_DIR}/_server_auto.py"

cat > "$SERVER_PY" << 'PYEOF'
import pathlib, glob, tempfile
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
import opendataloader_pdf

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
HERE = pathlib.Path(__file__).parent

@app.get("/")
def serve_ui():
    return FileResponse(HERE / "index.html")

@app.post("/convert")
async def convert(file: UploadFile = File(...), format: str = Form("html,markdown")):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "Only PDF files are supported")
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / file.filename
        p.write_bytes(await file.read())
        try:
            opendataloader_pdf.convert(
                input_path=[str(p)], output_dir=d,
                format="html,markdown", image_output="embedded", quiet=True
            )
        except Exception as e:
            raise HTTPException(500, detail=str(e))
        html = pathlib.Path(glob.glob(f"{d}/{p.stem}*.html")[0]).read_text("utf-8") if glob.glob(f"{d}/{p.stem}*.html") else ""
        md   = pathlib.Path(glob.glob(f"{d}/{p.stem}*.md")[0]).read_text("utf-8")   if glob.glob(f"{d}/{p.stem}*.md")   else ""
    return JSONResponse({"html": html, "markdown": md})
PYEOF

# Kill any existing server on that port
if lsof -ti tcp:${PORT} &>/dev/null; then
    warn "Killing existing process on port ${PORT}..."
    kill $(lsof -ti tcp:${PORT}) 2>/dev/null || true
    sleep 1
fi

# Launch server in background
"$PYTHON" -m uvicorn _server_auto:app --app-dir "$SCRIPT_DIR" --host 127.0.0.1 --port $PORT &
SERVER_PID=$!

# Wait until the server responds (up to 20 seconds)
TRIES=0
until curl -sf "http://localhost:${PORT}/docs" &>/dev/null; do
    sleep 1
    TRIES=$((TRIES+1))
    if [[ $TRIES -ge 20 ]]; then
        warn "Server taking longer than expected — opening browser anyway."
        break
    fi
done

info "Server is ready."

# Open browser
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "http://localhost:${PORT}"
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:${PORT}"
elif command -v gnome-open &>/dev/null; then
    gnome-open "http://localhost:${PORT}"
fi

echo
echo "============================================================"
echo "  Browser opened to http://localhost:${PORT}"
echo "  1. Upload a PDF using the file picker"
echo "  2. Click Convert and Download .docx"
echo "  Press Ctrl+C here to stop the server."
echo "============================================================"

# Keep running until Ctrl+C
wait $SERVER_PID
