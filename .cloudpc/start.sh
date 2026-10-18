#!/usr/bin/env bash
set -euo pipefail

port_open() {
    ss -ltn | grep -Eq ":${1}[[:space:]]"
}

echo "Starting Cloud PC..."

# Khoi dong XFCE / VNC neu chua chay
if ! port_open 5901; then
    vncserver :1 \
        -xstartup "$HOME/.vnc/xstartup" \
        -localhost yes \
        -geometry 1280x800 \
        -depth 24
else
    echo "VNC already running"
fi

# Khoi dong noVNC o che do background
if ! port_open 6080; then
    nohup websockify \
        --web=/usr/share/novnc \
        0.0.0.0:6080 \
        127.0.0.1:5901 \
        > /tmp/cloudpc-novnc.log 2>&1 < /dev/null &
    sleep 2
else
    echo "noVNC already running"
fi

if port_open 5901 && port_open 6080; then
    echo "========================="
    echo "Cloud PC is READY!"
    echo "VNC:   5901"
    echo "noVNC: 6080"
    echo "========================="
else
    echo "Startup failed. Check VNC and noVNC logs."
    tail -n 30 /tmp/cloudpc-novnc.log 2>/dev/null || true
    exit 1
fi
