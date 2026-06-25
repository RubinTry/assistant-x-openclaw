#!/bin/bash
# 语音助手启动脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
VENV_PYTHON="${PROJECT_DIR}/venv/bin/python"

# ── 芯片检测，自动选择最优 provider ────────────────────
if [[ $(uname -m) == "arm64" ]]; then
    PROVIDER="coreml"
elif [[ $(uname -m) == "x86_64" ]]; then
    PROVIDER="mps"
else
    PROVIDER="cpu"
fi
echo "[启动] 检测到芯片架构: $(uname -m)，使用 provider: $PROVIDER"

if [ ! -f "$VENV_PYTHON" ]; then
    echo "错误: 虚拟环境不存在，请先创建: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# 合并所有唤醒词文件到 global.txt
KEYWORDS_DIR="${PROJECT_DIR}/keywords"
GLOBAL_FILE="${KEYWORDS_DIR}/global.txt"

echo "合并唤醒词文件到 global.txt..."
# 删除旧的 global.txt
if [ -f "$GLOBAL_FILE" ]; then
    rm "$GLOBAL_FILE"
    echo "  已删除旧的 global.txt"
fi

# 创建新的 global.txt，合并所有 .txt 文件的唤醒词
touch "$GLOBAL_FILE"
for txt_file in "${KEYWORDS_DIR}"/*.txt; do
    # 跳过 global.txt 自身
    if [ "$(basename "$txt_file")" = "global.txt" ]; then
        continue
    fi
    
    if [ -f "$txt_file" ]; then
        echo "  合并: $(basename "$txt_file")"
        cat "$txt_file" >> "$GLOBAL_FILE"
        # 添加换行符（如果文件末尾没有）
        echo "" >> "$GLOBAL_FILE"
    fi
done

# 移除末尾多余的空行
if [ -f "$GLOBAL_FILE" ]; then
    # 使用 sed 移除末尾空行
    sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$GLOBAL_FILE" 2>/dev/null || true
fi

LINE_COUNT=$(wc -l < "$GLOBAL_FILE" 2>/dev/null || echo "0")
echo "✓ 已合并所有唤醒词到 global.txt (共 ${LINE_COUNT} 行)"
echo ""

# 检查是否有已运行的 jarvis_overlay
if pgrep -f "jarvis_overlay.*Debug" > /dev/null 2>&1; then
    echo "Debug 版 JARVIS Overlay 已在运行，跳过端口清理"
else
    # 杀掉占用端口的进程
    echo "清理占用端口的进程..."
    for port in 17888 17889; do
        PIDS=$(lsof -ti:$port 2>/dev/null)
        if [ -n "$PIDS" ]; then
            echo " 杀掉占用端口 $port 的进程: $PIDS"
            kill -9 $PIDS 2>/dev/null
        fi
    done
    sleep 1
fi

# 清理已有的语音助手进程（避免重启后出现多个实例）
echo "清理已有的语音助手进程..."
PIDS=$(pgrep -f "${PROJECT_DIR}/src/main.py" 2>/dev/null)
if [ -n "$PIDS" ]; then
    echo "  杀死旧的语音助手进程: $PIDS"
    kill -9 $PIDS 2>/dev/null
    sleep 1
fi

# 查找 JARVIS Overlay app
JARVIS_APP=""
DEBUG_APP="${PROJECT_DIR}/assistant_overlay/build/macos/Build/Products/Debug/assistant_overlay.app"
RELEASE_APP="${PROJECT_DIR}/assistant_overlay/build/macos/Build/Products/Release/assistant_overlay.app"
SYSTEM_APP="/Applications/assistant_overlay.app"

if pgrep -f "jarvis_overlay.*Debug" > /dev/null 2>&1; then
    echo "Debug 版 JARVIS Overlay 已在运行，使用已启动的实例"
elif [ -d "$DEBUG_APP" ]; then
    JARVIS_APP="$DEBUG_APP"
    echo "使用 Debug 版 JARVIS Overlay: $JARVIS_APP"
    echo "启动 JARVIS Overlay..."
    open "$JARVIS_APP"
    sleep 3
elif [ -d "$RELEASE_APP" ]; then
    JARVIS_APP="$RELEASE_APP"
    echo "使用 Release 版 JARVIS Overlay: $JARVIS_APP"
    echo "启动 JARVIS Overlay..."
    open "$JARVIS_APP"
    sleep 3
elif [ -d "$SYSTEM_APP" ]; then
    JARVIS_APP="$SYSTEM_APP"
    echo "使用系统安装版 JARVIS Overlay: $JARVIS_APP"
    echo "启动 JARVIS Overlay..."
    open "$JARVIS_APP"
    sleep 3
else
    echo "错误: 找不到 assistant_overlay.app"
    echo "请确保已构建 Flutter 项目，或已将 assistant_overlay.app 安装到 /Applications"
    echo ""
    echo "构建命令:"
    echo "  cd ${PROJECT_DIR}/jarvis_overlay"
    echo "  flutter build macos --debug    # Debug 版本"
    echo "  flutter build macos            # Release 版本"
    exit 1
fi

# ── 主脑引擎自愈：engine=hermes 时确保各角色 Hermes 网关在跑 ───────────
ENGINE=$("$VENV_PYTHON" -c "import json;print((json.load(open('${PROJECT_DIR}/assistants.json')).get('engine') or 'openclaw').strip().lower())" 2>/dev/null || echo openclaw)
HERMES_PIDS_FILE="${PROJECT_DIR}/.hermes_gateways.pids"
if [ "$ENGINE" = "hermes" ]; then
    echo "[引擎] hermes：校验各角色网关…"
    if "$VENV_PYTHON" "${SCRIPT_DIR}/hermes_provision.py"; then
        echo "[引擎] hermes：角色网关就绪"
    else
        echo "[引擎] hermes：角色网关自愈失败，请检查 hermes 安装与模型凭证"
        exit 1
    fi
else
    echo "[引擎] ${ENGINE}：跳过 Hermes 自愈"
fi

cleanup() {
    echo "正在关闭..."
    for port in 17888 17889; do
        PIDS=$(lsof -ti:$port 2>/dev/null)
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS 2>/dev/null
        fi
    done
    # 关闭由本脚本拉起的各角色 Hermes 网关（若有）
    if [ "$ENGINE" = "hermes" ] && [ -f "$HERMES_PIDS_FILE" ]; then
        while read -r VPID; do
            [ -n "$VPID" ] && kill "$VPID" 2>/dev/null && echo "  已关闭 Hermes 网关 (pid=$VPID)"
        done < "$HERMES_PIDS_FILE"
        rm -f "$HERMES_PIDS_FILE"
    fi
    osascript -e 'quit app "jarvis_overlay"' 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "启动语音助手..."
cd "${PROJECT_DIR}"
"$VENV_PYTHON" -u "${PROJECT_DIR}/src/main.py" --provider "$PROVIDER" "$@"