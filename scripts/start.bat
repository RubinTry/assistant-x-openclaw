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

:: 合并所有唤醒词文件到 global.txt
set "KEYWORDS_DIR=%PROJECT_DIR%\keywords"
set "GLOBAL_FILE=%KEYWORDS_DIR%\global.txt"

echo 合并唤醒词文件到 global.txt...

:: 删除旧的 global.txt
if exist "%GLOBAL_FILE%" (
    del "%GLOBAL_FILE%"
    echo   已删除旧的 global.txt
)

:: 创建新的 global.txt，合并所有 .txt 文件的唤醒词
type nul > "%GLOBAL_FILE%"
for %%f in ("%KEYWORDS_DIR%\*.txt") do (
    set "FILENAME=%%~nxf"
    if not "!FILENAME!"=="global.txt" (
        echo   合并: !FILENAME!
        type "%%f" >> "%GLOBAL_FILE%"
        echo. >> "%GLOBAL_FILE%"
    )
)

:: 统计行数
for /f %%c in ('find /c /v "" ^< "%GLOBAL_FILE%"') do set "LINE_COUNT=%%c"
echo ✓ 已合并所有唤醒词到 global.txt (共 %LINE_COUNT% 行)
echo.

:: 清理占用端口的进程
echo 清理占用端口的进程...
for %%p in (17888 17889) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%%p ^| findstr LISTENING') do (
        echo  杀掉占用端口 %%p 的进程: %%a
        taskkill /F /PID %%a >nul 2>&1
    )
)
timeout /t 1 >nul

:: TODO: Windows 上的 assistant_overlay 特效尚未适配，暂不启动
:: 待适配后，取消下方注释，并根据实际路径修改 overlay 路径
::
:: set "OVERLAY_FOUND=0"
:: set "DEBUG_APP=%PROJECT_DIR%\assistant_overlay\build\windows\x64\runner\Debug\assistant_overlay.exe"
:: set "RELEASE_APP=%PROJECT_DIR%\assistant_overlay\build\windows\x64\runner\Release\assistant_overlay.exe"
::
:: :: 检查是否已有 overlay 运行
:: tasklist /FI "IMAGENAME eq assistant_overlay.exe" 2>nul | find /I "assistant_overlay.exe" >nul
:: if !errorlevel! equ 0 (
::     echo Debug 版 Assistant Overlay 已在运行，使用已启动的实例
::     set "OVERLAY_FOUND=1"
:: ) else if exist "%DEBUG_APP%" (
::     set "OVERLAY_FOUND=1"
::     echo 使用 Debug 版 Assistant Overlay
::     start "" "%DEBUG_APP%"
::     timeout /t 2 >nul
:: ) else if exist "%RELEASE_APP%" (
::     set "OVERLAY_FOUND=1"
::     echo 使用 Release 版 Assistant Overlay
::     start "" "%RELEASE_APP%"
::     timeout /t 2 >nul
:: )
::
:: if !OVERLAY_FOUND! equ 0 (
::     echo 注意: 找不到 assistant_overlay.exe，暂不启动视觉特效
:: )

echo 注意: JARVIS Overlay (Flutter HUD 特效) 暂不支持 Windows，仅启动语音助手主体。
echo 如需视觉特效，请使用 macOS 版本。
echo.

echo 启动语音助手...
cd /d "%PROJECT_DIR%"
"%VENV_PYTHON%" "%PROJECT_DIR%\src\main.py" %*
