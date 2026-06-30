@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpi"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "PROJECT_NAME=control_center"
set "BUILD_TYPE=%BUILD_TYPE%"
if "%BUILD_TYPE%"=="" set "BUILD_TYPE=release"

echo Building %PROJECT_NAME% (%BUILD_TYPE%)...
cd /d "%PROJECT_DIR%"

if /i "%BUILD_TYPE%"=="debug" (
    flutter build windows --debug
) else (
    flutter build windows --release
)

if errorlevel 1 (
    echo Error: flutter build windows failed
    exit /b 1
)

echo Creating MSIX installer...
if /i "%BUILD_TYPE%"=="debug" (
    dart run msix:create --debug
) else (
    dart run msix:create
)

if errorlevel 1 (
    echo Error: msix:create failed
    exit /b 1
)

echo.
echo Done: %PROJECT_NAME%.msix
echo MSIX file location: %PROJECT_DIR%\build\windows\x64\runner\%BUILD_TYPE%\%PROJECT_NAME%.msix

start "" explorer "%PROJECT_DIR%\build\windows\x64\runner\%BUILD_TYPE%"

flutter clean

endlocal
