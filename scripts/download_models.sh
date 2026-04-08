#!/bin/bash
# 模型下载脚本 - macOS/Linux
# 用法: ./download_models.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
MODELS_DIR="${PROJECT_DIR}/models"
TOOLS_DIR="${HOME}/.openclaw/tools/sherpa-onnx-tts"

echo "===== JARVIS 模型下载工具 ====="
echo "项目目录: ${PROJECT_DIR}"
echo ""

mkdir -p "${MODELS_DIR}"
mkdir -p "${TOOLS_DIR}/models"
mkdir -p "${PROJECT_DIR}/data/voices"

download_and_extract() {
    local name="$1"
    local url="$2"
    local dest_dir="$3"
    local filename="$4"
    
    echo "[${name}]"
    if [ -n "${filename}" ]; then
        local full_path="${dest_dir}/${filename}"
    else
        local full_path="${dest_dir}"
    fi
    
    if [ -d "${full_path}" ] || [ -f "${full_path}" ]; then
        echo "  已存在，跳过: ${full_path}"
        echo ""
        return 0
    fi
    
    echo "  下载: ${url}"
    cd "${dest_dir}"
    
    if command -v curl &> /dev/null; then
        curl -L -o "${filename}.tmp" "${url}"
    elif command -v wget &> /dev/null; then
        wget -O "${filename}.tmp" "${url}"
    else
        echo "  错误: 需要 curl 或 wget"
        return 1
    fi
    
    if [[ "${filename}" == *.tar.bz2 ]]; then
        tar -xjf "${filename}.tmp"
    elif [[ "${filename}" == *.tar.gz ]]; then
        tar -xzf "${filename}.tmp"
    elif [[ "${filename}" == *.zip ]]; then
        unzip -o "${filename}.tmp"
    else
        mv "${filename}.tmp" "${filename}"
        return 0
    fi
    
    rm -f "${filename}.tmp"
    echo "  完成: ${full_path}"
    echo ""
}

echo "----- 1. KWS 唤醒词模型 -----"
download_and_extract \
    "KWS 唤醒词模型" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2" \
    "${MODELS_DIR}" \
    "sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2"

echo "----- 2. ASR 语音识别模型 -----"
download_and_extract \
    "ASR 语音识别模型" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2" \
    "${MODELS_DIR}" \
    "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2"

echo "----- 3. TTS 模型 (ZipVoice) -----"
download_and_extract \
    "ZipVoice 模型" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2" \
    "${TOOLS_DIR}/models" \
    "sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2"

echo "----- 4. Vocos Vocoder -----"
VOCOS_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vocos_24khz.onnx"
if [ ! -f "${MODELS_DIR}/vocos_24khz.onnx" ]; then
    echo "[Vocos Vocoder]"
    echo "  下载: ${VOCOS_URL}"
    cd "${MODELS_DIR}"
    curl -L -o "vocos_24khz.onnx.tmp" "${VOCOS_URL}"
    mv "vocos_24khz.onnx.tmp" "vocos_24khz.onnx"
    echo "  完成: ${MODELS_DIR}/vocos_24khz.onnx"
else
    echo "[Vocos Vocoder] 已存在，跳过"
fi
echo ""

echo "----- 5. JARVIS 参考音频 -----"
JARVIS_AUDIO_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/jarvis_start_up.mp3"
if [ ! -f "${PROJECT_DIR}/data/voices/jarvis_start_up.mp3" ]; then
    echo "[JARVIS 参考音频]"
    echo "  下载: ${JARVIS_AUDIO_URL}"
    cd "${PROJECT_DIR}/data/voices"
    curl -L -o "jarvis_start_up.mp3.tmp" "${JARVIS_AUDIO_URL}"
    mv "jarvis_start_up.mp3.tmp" "jarvis_start_up.mp3"
    echo "  完成: ${PROJECT_DIR}/data/voices/jarvis_start_up.mp3"
else
    echo "[JARVIS 参考音频] 已存在，跳过"
fi
echo ""

echo "===== 可选模型 ====="
echo "如需 Qwen3-ASR 离线识别模式，请手动下载:"
echo "  https://k2-fsa.github.io/sherpa/onnx/pretrained_models/qwen3.html"
echo ""
echo "===== 下载完成 ====="
echo "所有必需模型已下载到:"
echo "  KWS/ASR: ${MODELS_DIR}/"
echo "  TTS: ${TOOLS_DIR}/models/"
