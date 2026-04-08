@echo off
chcp 65001 >nul
:: 语音助手启动脚本 (Windows)

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpi"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "VENV_PYTHON=%PROJECT_DIR%\venv\Scripts\python.exe"

if not exist "%VENV_PYTHON%" (
    echo 错误: 虚拟环境不存在，请先创建:
    echo   python -m venv venv
    echo   venv\Scripts\activate
    echo   pip install -r requirements.txt
    exit /b 1
)

echo 清理占用端口的进程...
for %%p in (17888 17889) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%%p ^| findstr LISTENING') do (
        echo  杀掉占用端口 %%p 的进程: %%a
        taskkill /F /PID %%a >nul 2>&1
    )
)
timeout /t 1 >nul

echo.
echo 注意: JARVIS Overlay (Flutter HUD 特效) 暂不支持 Windows，仅启动语音助手主体。
echo 如需视觉特效，请使用 macOS 版本。
echo.

echo 启动语音助手...
cd /d "%PROJECT_DIR%"
"%VENV_PYTHON%" "%PROJECT_DIR%\src\main.py" %*
