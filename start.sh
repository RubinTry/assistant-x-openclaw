#!/bin/bash
# 语音助手启动脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_PYTHON="${SCRIPT_DIR}/venv/bin/python"

if [ ! -f "$VENV_PYTHON" ]; then
    echo "错误: 虚拟环境不存在，请先创建: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# 杀掉占用端口的进程
echo "清理占用端口的进程..."
for port in 17888 17889; do
    PIDS=$(lsof -ti:$port 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "  杀掉占用端口 $port 的进程: $PIDS"
        kill -9 $PIDS 2>/dev/null
    fi
done

sleep 1

echo "启动 JARVIS Overlay..."
xcrun swift "${SCRIPT_DIR}/jarvis_overlay.swift" &
SWIFT_PID=$!
sleep 2

cleanup() {
    echo "正在关闭..."
    kill $SWIFT_PID 2>/dev/null
    for port in 17888 17889; do
        PIDS=$(lsof -ti:$port 2>/dev/null)
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS 2>/dev/null
        fi
    done
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "启动语音助手..."
"$VENV_PYTHON" "${SCRIPT_DIR}/main.py" "$@"
