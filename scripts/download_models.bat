@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%i in ("%SCRIPT_DIR%") do set "PROJECT_DIR=%%~dpi"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "MODELS_DIR=%PROJECT_DIR%\models"
set "TOOLS_DIR=%USERPROFILE%\.openclaw\tools\sherpa-onnx-tts"

echo ===== JARVIS Model Download Tool =====
echo Project dir: %PROJECT_DIR%
echo.

if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"
if not exist "%TOOLS_DIR%\models" mkdir "%TOOLS_DIR%\models"
if not exist "%PROJECT_DIR%\data\voices" mkdir "%PROJECT_DIR%\data\voices"

set "KWS_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2"
set "ASR_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2"
set "TTS_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2"
set "VOCOS_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vocos_24khz.onnx"
set "JARVIS_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/jarvis_start_up.mp3"

echo ----- 1. KWS Model -----
if exist "%MODELS_DIR%\sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01" (
    echo   Already exists, skipping
) else (
    echo   Downloading KWS model...
    powershell -Command "Invoke-WebRequest -Uri '%KWS_URL%' -OutFile '%MODELS_DIR%\kws.tar.bz2'"
    echo   Extracting with tar...
    tar -xjf "%MODELS_DIR%\kws.tar.bz2" -C "%MODELS_DIR%"
    del /f /q "%MODELS_DIR%\kws.tar.bz2"
    echo   Done
)
echo.

echo ----- 2. ASR Model -----
if exist "%MODELS_DIR%\sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" (
    echo   Already exists, skipping
) else (
    echo   Downloading ASR model...
    powershell -Command "Invoke-WebRequest -Uri '%ASR_URL%' -OutFile '%MODELS_DIR%\asr.tar.bz2'"
    echo   Extracting with tar...
    tar -xjf "%MODELS_DIR%\asr.tar.bz2" -C "%MODELS_DIR%"
    del /f /q "%MODELS_DIR%\asr.tar.bz2"
    echo   Done
)
echo.

echo ----- 3. TTS Model (ZipVoice) -----
if exist "%TOOLS_DIR%\models\sherpa-onnx-zipvoice-distill-int8-zh-en-emilia" (
    echo   Already exists, skipping
) else (
    echo   Downloading TTS model...
    powershell -Command "Invoke-WebRequest -Uri '%TTS_URL%' -OutFile '%TOOLS_DIR%\models\tts.tar.bz2'"
    echo   Extracting with tar...
    tar -xjf "%TOOLS_DIR%\models\tts.tar.bz2" -C "%TOOLS_DIR%\models"
    del /f /q "%TOOLS_DIR%\models\tts.tar.bz2"
    echo   Done
)
echo.

echo ----- 4. Vocos Vocoder -----
if exist "%MODELS_DIR%\vocos_24khz.onnx" (
    echo   Already exists, skipping
) else (
    echo   Downloading Vocos...
    powershell -Command "Invoke-WebRequest -Uri '%VOCOS_URL%' -OutFile '%MODELS_DIR%\vocos_24khz.onnx'"
    echo   Done
)
echo.

echo ----- 5. JARVIS Reference Audio -----
if exist "%PROJECT_DIR%\data\voices\jarvis_start_up.mp3" (
    echo   Already exists, skipping
) else (
    echo   Downloading JARVIS audio...
    powershell -Command "Invoke-WebRequest -Uri '%JARVIS_URL%' -OutFile '%PROJECT_DIR%\data\voices\jarvis_start_up.mp3'"
    echo   Done
)
echo.

echo ===== Optional Models =====
echo For Qwen3-ASR offline mode, download manually:
echo   https://k2-fsa.github.io/sherpa/onnx/pretrained_models/qwen3.html
echo.
echo ===== Download Complete =====
echo All required models downloaded to:
echo   KWS/ASR: %MODELS_DIR%\
echo   TTS: %TOOLS_DIR%\models\
pause
