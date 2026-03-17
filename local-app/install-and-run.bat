@echo off
setlocal enabledelayedexpansion
title PDF to Word Converter - Setup
color 0A

echo ============================================================
echo  PDF to Word Converter ^|  Powered by OpenDataLoader
echo ============================================================
echo.

:: ---------------------------------------------------------------
:: HELPER: find_java - uses PowerShell to locate java.exe anywhere
:: under Program Files and injects it into PATH for this session.
:: ---------------------------------------------------------------
:find_java
for /f "delims=" %%J in ('powershell -NoProfile -Command "$j = Get-ChildItem -Path 'C:\Program Files' -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'javapath' } | Select-Object -First 1; if ($j) { $j.DirectoryName } else { '' }" 2^>nul') do (
    if not "%%J"=="" (
        set "PATH=%%J;!PATH!"
        echo Java located at %%J
        goto JAVA_OK
    )
)
goto :eof

:: ---------------------------------------------------------------
:: STEP 1 - Check / Install Java
:: ---------------------------------------------------------------
echo [1/4] Checking for Java...

java -version >nul 2>&1
if %errorlevel% equ 0 goto JAVA_OK

:: Not on PATH - try to find it already installed
call :find_java
java -version >nul 2>&1
if %errorlevel% equ 0 goto JAVA_OK

:: Truly not installed - download and install
echo Java not found. Downloading Java 21 JRE ^(~50 MB one-time^)...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.3+9/OpenJDK21U-jre_x64_windows_hotspot_21.0.3_9.msi' -OutFile '$env:TEMP\java_installer.msi' -UseBasicParsing"
if !errorlevel! neq 0 ( echo ERROR: Java download failed. Check internet. & pause & exit /b 1 )
echo Installing Java...
msiexec /i "%TEMP%\java_installer.msi" /quiet /norestart ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome
echo Waiting for installer to finish...
timeout /t 8 /nobreak >nul

:: Now find it using PowerShell (works regardless of install folder name)
call :find_java
java -version >nul 2>&1
if %errorlevel% equ 0 goto JAVA_OK

echo ERROR: Java install failed or could not be located.
echo Please install Java manually from https://adoptium.net and re-run.
pause & exit /b 1

:JAVA_OK
echo Java found. OK.

:: ---------------------------------------------------------------
:: STEP 2 - Check / Install Python
:: ---------------------------------------------------------------
echo.
echo [2/4] Checking for Python...

python --version >nul 2>&1
set PYTHON_CMD=python
if %errorlevel% equ 0 goto PYTHON_OK

py --version >nul 2>&1
if %errorlevel% equ 0 ( set PYTHON_CMD=py & goto PYTHON_OK )

:: Try to find Python already installed via PowerShell
for /f "delims=" %%P in ('powershell -NoProfile -Command "$p = Get-ChildItem -Path @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'WindowsApps' } | Select-Object -First 1; if ($p) { $p.DirectoryName } else { '' }" 2^>nul') do (
    if not "%%P"=="" (
        set "PATH=%%P;%%P\Scripts;!PATH!"
        set PYTHON_CMD=python
        echo Found Python at %%P
        goto PYTHON_OK
    )
)

:: Not installed - download and install
echo Python not found. Downloading Python 3.12 ^(~25 MB one-time^)...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe' -OutFile '$env:TEMP\python_installer.exe' -UseBasicParsing"
if !errorlevel! neq 0 ( echo ERROR: Python download failed. Check internet. & pause & exit /b 1 )
echo Installing Python...
"%TEMP%\python_installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
echo Waiting for installer to finish...
timeout /t 8 /nobreak >nul

:: Find freshly installed Python via PowerShell
for /f "delims=" %%P in ('powershell -NoProfile -Command "$p = Get-ChildItem -Path @($env:LOCALAPPDATA, $env:ProgramFiles) -Recurse -Filter python.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'WindowsApps' } | Select-Object -First 1; if ($p) { $p.DirectoryName } else { '' }" 2^>nul') do (
    if not "%%P"=="" (
        set "PATH=%%P;%%P\Scripts;!PATH!"
        set PYTHON_CMD=python
        echo Python located at %%P
        goto PYTHON_OK
    )
)

echo ERROR: Python install failed or could not be located.
echo Please install Python manually from https://python.org and re-run.
pause & exit /b 1

:PYTHON_OK
echo Python found. OK.

:: ---------------------------------------------------------------
:: STEP 3 - Install Python packages
:: ---------------------------------------------------------------
echo.
echo [3/4] Installing required packages ^(first run: ~1-2 min^)...
%PYTHON_CMD% -m pip install --quiet --upgrade pip
%PYTHON_CMD% -m pip install --quiet opendataloader-pdf fastapi "uvicorn[standard]" python-multipart
if %errorlevel% neq 0 (
    echo ERROR: Package install failed. Try right-clicking and "Run as administrator".
    pause & exit /b 1
)
echo Packages ready.

:: ---------------------------------------------------------------
:: STEP 4 - Write embedded server + launch
:: ---------------------------------------------------------------
echo.
echo [4/4] Starting PDF converter at http://localhost:8000 ...
set SCRIPT_DIR=%~dp0
set SERVER_PY=%SCRIPT_DIR%_server_auto.py

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
echo         md_files = glob.glob(f"{d}/{p.stem}*.md")
echo         html = pathlib.Path(html_files[0]).read_text("utf-8") if html_files else ""
echo         md = pathlib.Path(md_files[0]).read_text("utf-8") if md_files else ""
echo         return JSONResponse({"html": html, "markdown": md})
) > "%SERVER_PY%"

:: Kill any old server on port 8000
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8000 " ^| findstr LISTENING') do (
    taskkill /PID %%a /F >nul 2>&1
)

:: Start server
start "OpenDataLoader PDF Server" /min %PYTHON_CMD% -m uvicorn _server_auto:app --app-dir "%SCRIPT_DIR%" --host 127.0.0.1 --port 8000

:: Wait up to 20s for server to be ready
set /a tries=0
:WAIT_LOOP
timeout /t 1 /nobreak >nul
set /a tries+=1
powershell -NoProfile -Command "try{(Invoke-WebRequest -Uri http://localhost:8000 -UseBasicParsing -TimeoutSec 1).StatusCode}catch{exit 1}" >nul 2>&1
if %errorlevel% neq 0 (
    if !tries! lss 20 goto WAIT_LOOP
    echo WARNING: Server slow to start. Opening browser anyway...
)
echo Server is ready.
start http://localhost:8000
echo.
echo ============================================================
echo  Browser opened to http://localhost:8000
echo.
echo  1. Upload a PDF using the file picker.
echo  2. Click "Convert and Download .docx"
echo.
echo  To stop: close the "OpenDataLoader PDF Server" window.
echo ============================================================
echo.
pause
