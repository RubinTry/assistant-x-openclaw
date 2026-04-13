#!/bin/bash
# 语音助手启动脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
VENV_PYTHON="${PROJECT_DIR}/venv/bin/python"

if [ ! -f "$VENV_PYTHON" ]; then
    echo "错误: 虚拟环境不存在，请先创建: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

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