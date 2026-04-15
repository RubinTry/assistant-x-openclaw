#!/bin/bash
# 语音助手启动脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
VENV_PYTHON="${PROJECT_DIR}/venv/bin/python"

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

cleanup() {
    echo "正在关闭..."
    for port in 17888 17889; do
        PIDS=$(lsof -ti:$port 2>/dev/null)
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS 2>/dev/null
        fi
    done
    osascript -e 'quit app "jarvis_overlay"' 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "启动语音助手..."
cd "${PROJECT_DIR}"
"$VENV_PYTHON" "${PROJECT_DIR}/src/main.py" "$@"