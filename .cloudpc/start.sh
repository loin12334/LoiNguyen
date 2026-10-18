#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-normal}"

port_open() {
    ss -ltnH | awk -v p="$1" '
      $4 ~ (":" p "$") { found=1 }
      END { exit !found }
    '
}

echo "=============================="
echo "       MY CLOUD PC"
echo "=============================="


# CLOUDPC AUDIO BEFORE XFCE
if /workspaces/LoiNguyen/.cloudpc/audio-start.sh; then
    source /workspaces/LoiNguyen/.cloudpc/audio-env.sh
else
    echo "[WARNING] Audio unavailable; continuing with desktop."
fi

# 1. Start VNC
if ! port_open 5901; then
    echo "[1/3] Starting XFCE..."

    vncserver :1 \
        -xstartup "$HOME/.vnc/xstartup" \
        -localhost yes \
        -geometry 1280x800 \
        -depth 24
else
    echo "[1/3] XFCE already running"
fi

# 2. Start noVNC
if ! port_open 6080; then
    echo "[2/3] Starting noVNC..."

    nohup websockify \
        --web=/usr/share/novnc \
        0.0.0.0:6080 \
        127.0.0.1:5901 \
        > /tmp/cloudpc-novnc.log 2>&1 < /dev/null &

    sleep 2
else
    echo "[2/3] noVNC already running"
fi

# Check
if ! port_open 5901 || ! port_open 6080; then
    echo "ERROR: Cloud PC startup failed!"
    exit 1
fi

echo ""
echo "=============================="
echo "    CLOUD PC IS READY!"
echo "=============================="
echo "RAM:     $(free -h | awk '/Mem:/ {print $2}')"
echo "VNC:     5901"
echo "noVNC:   6080"
echo "=============================="

# Optional: Start without keep-alive
if [[ "$MODE" == "--no-keepalive" ]]; then
    exit 0
fi

# 3. Keep Alive
echo ""
echo "[3/3] Keep-Alive enabled"
echo "Interval: 240 seconds"
echo "Press Ctrl+C to stop Keep-Alive."
echo ""

trap 'echo "Keep-Alive stopped."; exit 0' INT TERM

while true; do
    echo "[KEEP-ALIVE] $(date '+%H:%M:%S') - Cloud PC active"
    sleep 240
done
