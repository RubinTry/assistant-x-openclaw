#!/bin/bash
# 语音助手保活重启脚本
# 功能：检查并重启语音助手，如果已在运行则先停止

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
START_SCRIPT="${SCRIPT_DIR}/start.sh"
PID_FILE="/tmp/voice_assistant.pid"

echo "=== 语音助手保活脚本 ==="
echo "时间: $(date)"
echo ""

# 1. 检查 PID 文件
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ]; then
        if kill -0 "$PID" 2>/dev/null; then
            echo "[1/3] 检测到运行中的进程 (PID: $PID)，正在停止..."
            kill -9 "$PID" 2>/dev/null
            sleep 1
            # 再次检查
            if kill -0 "$PID" 2>/dev/null; then
                echo "  警告: 进程未能停止，尝试强制终止..."
                kill -9 "$PID" 2>/dev/null
                sleep 1
            fi
        fi
    fi
    rm -f "$PID_FILE"
    echo "[1/3] 已清理 PID 文件"
else
    echo "[1/3] 无 PID 文件，检查端口..."
fi

echo ""

# 2. 检查端口（双重保险）
echo "[2/3] 检查端口占用..."
FOUND_PROCESS=false
for port in 17888 17889; do
    PIDS=$(lsof -ti:$port 2>/dev/null)
    if [ -n "$PIDS" ]; then
        FOUND_PROCESS=true
        echo "  端口 $port 被占用，进程: $PIDS"
        for pid in $PIDS; do
            kill -9 "$pid" 2>/dev/null
        done
    fi
done

if [ "$FOUND_PROCESS" = true ]; then
    echo "  已清理端口占用进程"
    sleep 1
else
    echo "  端口未被占用"
fi

echo ""

# 3. 额外检查：直接查找相关进程
echo "[3/3] 检查残留进程..."
RESIDUAL_PIDS=$(pgrep -f "python.*main\.py|swift.*jarvis_overlay" 2>/dev/null)
if [ -n "$RESIDUAL_PIDS" ]; then
    echo "  发现残留进程: $RESIDUAL_PIDS"
    for pid in $RESIDUAL_PIDS; do
        kill -9 "$pid" 2>/dev/null
    done
    echo "  已清理残留进程"
    sleep 1
else
    echo "  无残留进程"
fi

echo ""
echo "=== 启动语音助手 ==="

# 检查 start.sh 是否存在
if [ ! -f "$START_SCRIPT" ]; then
    echo "错误: 启动脚本不存在: $START_SCRIPT"
    exit 1
fi

# 启动
exec "$START_SCRIPT"
