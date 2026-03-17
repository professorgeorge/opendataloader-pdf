@echo off
setlocal enabledelayedexpansion
title PDF to Word Converter - Setup
color 0A

echo ============================================================
echo   PDF to Word Converter  ^|  Powered by OpenDataLoader
echo ============================================================
echo.

:: ---------------------------------------------------------------
:: STEP 1 - Check / Install Java (required by OpenDataLoader)
:: ---------------------------------------------------------------
echo [1/4] Checking for Java...
java -version >nul 2>&1
if %errorlevel% neq 0 (
    echo      Java not found. Downloading Java 21 JRE ^(~50 MB one-time^)...
    powershell -Command "Invoke-WebRequest -Uri https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3+9/OpenJDK21U-jre_x64_windows_hotspot_21.0.3_9.msi -OutFile %TEMP%\java_installer.msi -UseBasicParsing"
    if !errorlevel! neq 0 ( echo ERROR: Java download failed. Check internet. & pause & exit /b 1 )
    echo      Installing Java...
    msiexec /i "%TEMP%\java_installer.msi" /quiet /norestart ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome
    echo      Refreshing PATH...
    call refreshenv.cmd >nul 2>&1
    java -version >nul 2>&1
    if !errorlevel! neq 0 (
        echo      Java installed. Please CLOSE and RE-RUN this script to continue.
        pause & exit /b 0
    )
) else (
    echo      Java found. OK.
)

:: ---------------------------------------------------------------
:: STEP 2 - Check / Install Python
:: ---------------------------------------------------------------
echo.
echo [2/4] Checking for Python...
python --version >nul 2>&1
set PYTHON_CMD=python
if %errorlevel% neq 0 (
    py --version >nul 2>&1
    if !errorlevel! equ 0 (
        set PYTHON_CMD=py
        echo      Python found via py launcher. OK.
    ) else (
        echo      Python not found. Downloading Python 3.12 ^(~25 MB one-time^)...
        powershell -Command "Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe -OutFile %TEMP%\python_installer.exe -UseBasicParsing"
        if !errorlevel! neq 0 ( echo ERROR: Python download failed. Check internet. & pause & exit /b 1 )
        echo      Installing Python ^(added to PATH^)...
        "%TEMP%\python_installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
        echo      Python installed. Please CLOSE and RE-RUN this script to continue.
        pause & exit /b 0
    )
) else (
    echo      Python found. OK.
)

:: ---------------------------------------------------------------
:: STEP 3 - Install Python packages
:: ---------------------------------------------------------------
echo.
echo [3/4] Installing required packages ^(first run: ~1-2 min^)...
%PYTHON_CMD% -m pip install --quiet --upgrade pip
%PYTHON_CMD% -m pip install --quiet opendataloader-pdf fastapi "uvicorn[standard]" python-multipart
if %errorlevel% neq 0 (
    echo ERROR: Package install failed. Try right-clicking this file and "Run as administrator".
    pause & exit /b 1
)
echo      Packages ready.

:: ---------------------------------------------------------------
:: STEP 4 - Write embedded server script + launch everything
:: ---------------------------------------------------------------
echo.
echo [4/4] Starting PDF converter at http://localhost:8000 ...

set SCRIPT_DIR=%~dp0
set SERVER_PY=%SCRIPT_DIR%_server_auto.py

:: Write the FastAPI server script
(
echo import sys, pathlib, glob, tempfile
echo from fastapi import FastAPI, File, Form, UploadFile, HTTPException
echo from fastapi.middleware.cors import CORSMiddleware
echo from fastapi.responses import JSONResponse, FileResponse
echo import opendataloader_pdf
echo.
echo app = FastAPI()
echo app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
echo.
echo HERE = pathlib.Path(__file__).parent
echo.
echo @app.get("/")
echo def serve_ui():
echo     return FileResponse(HERE / "index.html")
echo.
echo @app.post("/convert")
echo async def convert(file: UploadFile = File(...), format: str = Form("html,markdown")):
echo     if not file.filename.lower().endswith(".pdf"):
echo         raise HTTPException(400, "Only PDF files are supported")
echo     with tempfile.TemporaryDirectory() as d:
echo         p = pathlib.Path(d) / file.filename
echo         p.write_bytes(await file.read())
echo         try:
echo             opendataloader_pdf.convert(input_path=[str(p)], output_dir=d, format="html,markdown", image_output="embedded", quiet=True)
echo         except Exception as e:
echo             raise HTTPException(500, detail=str(e))
echo         html_files = glob.glob(f"{d}/{p.stem}*.html")
echo         md_files   = glob.glob(f"{d}/{p.stem}*.md")
echo         html = pathlib.Path(html_files[0]).read_text("utf-8") if html_files else ""
echo         md   = pathlib.Path(md_files[0]).read_text("utf-8")   if md_files   else ""
echo     return JSONResponse({"html": html, "markdown": md})
) > "%SERVER_PY%"

:: Kill any old server on port 8000
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8000 " ^| findstr LISTENING') do (
    taskkill /PID %%a /F >nul 2>&1
)

:: Start server in a minimised window
start "OpenDataLoader PDF Server" /min %PYTHON_CMD% -m uvicorn _server_auto:app --app-dir "%SCRIPT_DIR%" --host 127.0.0.1 --port 8000

:: Wait for server to be ready (up to 15s)
set /a tries=0
:WAIT_LOOP
timeout /t 1 /nobreak >nul
set /a tries+=1
powershell -Command "try { (Invoke-WebRequest -Uri http://localhost:8000/docs -UseBasicParsing -TimeoutSec 1).StatusCode } catch { exit 1 }" >nul 2>&1
if %errorlevel% neq 0 (
    if !tries! lss 15 goto WAIT_LOOP
    echo WARNING: Server may still be starting. Opening browser anyway...
)

echo      Server is ready.
start http://localhost:8000

echo.
echo ============================================================
echo   Browser opened to http://localhost:8000
echo.
echo   1. Upload a PDF using the file picker.
echo   2. Click "Convert and Download .docx"
echo.
echo   To stop the server, close the "OpenDataLoader PDF Server"
echo   window, or press Ctrl+C in that window.
echo ============================================================
echo.
pause
