@echo off
chcp 65001 >nul

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpi"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "VENV_PYTHON=%PROJECT_DIR%\venv\Scripts\python.exe"

if not exist "%VENV_PYTHON%" (
    echo Error: Virtual environment not found. Run:
    echo   python -m venv venv
    echo   venv\Scripts\activate
    echo   pip install -r requirements.txt
    exit /b 1
)

set "KEYWORDS_DIR=%PROJECT_DIR%\keywords"
set "GLOBAL_FILE=%KEYWORDS_DIR%\global.txt"

echo Merging wake word files...
if exist "%GLOBAL_FILE%" del "%GLOBAL_FILE%"
type nul > "%GLOBAL_FILE%"

for %%f in ("%KEYWORDS_DIR%\*.txt") do (
    set "FILENAME=%%~nxf"
    if not "!FILENAME!"=="global.txt" (
        echo   Merging: !FILENAME!
        type "%%f" >> "%GLOBAL_FILE%"
        echo. >> "%GLOBAL_FILE%"
    )
)

for %%c in ('powershell -Command "(Get-Content '%GLOBAL_FILE%' | Measure-Object -Line).Lines"') do set "LINE_COUNT=%%c"
echo Done: Merged %LINE_COUNT% wake words to global.txt
echo.

echo Cleaning up existing processes...
taskkill /F /IM python.exe 2>nul
taskkill /F /IM pythonw.exe 2>nul
taskkill /F /IM windows_system_audio_capture.exe 2>nul
taskkill /F /IM assistant_overlay.exe 2>nul
ping -n 2 127.0.0.1 >nul

echo Cleaning up ports 17888 and 17889...
for %%p in (17888 17889) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%%p ^| findstr LISTENING') do (
        echo   Killing process on port %%p: %%a
        taskkill /F /PID %%a >nul 2>&1
    )
)
ping -n 2 127.0.0.1 >nul

echo Starting JARVIS Overlay...
powershell -ExecutionPolicy Bypass -NoProfile -File "%PROJECT_DIR%\scripts\launch_overlay.ps1" < nul
ping -n 3 127.0.0.1 >nul

echo Starting voice assistant...
cd /d "%PROJECT_DIR%"
"%VENV_PYTHON%" "%PROJECT_DIR%\src\main.py" %*

echo Cleaning up on exit...
taskkill /F /IM assistant_overlay.exe 2>nul
for %%p in (17888 17889) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%%p ^| findstr LISTENING') do (
        taskkill /F /PID %%a >nul 2>&1
    )
)
