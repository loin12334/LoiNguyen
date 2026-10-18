#!/usr/bin/env bash
set -euo pipefail

DIR="/workspaces/LoiNguyen/.cloudpc"
VENV="$HOME/.local/share/cloudpc-audio-venv"

echo "[AUDIO] Initializing WebSocket audio..."

# Remove stale environment from previous sessions
unset PULSE_SERVER
unset XDG_RUNTIME_DIR

if ! pactl info >/dev/null 2>&1; then
    pulseaudio --start --exit-idle-time=-1
    sleep 1
fi

PA_SOCKET=$(LC_ALL=C pactl info |
    sed -n 's/^Server String: //p' | head -n 1)

if [[ "$PA_SOCKET" == unix:* ]]; then
    export PULSE_SERVER="$PA_SOCKET"
elif [[ "$PA_SOCKET" == /* ]]; then
    export PULSE_SERVER="unix:$PA_SOCKET"
else
    echo "[ERROR] Cannot detect PulseAudio socket"
    exit 1
fi

export XDG_RUNTIME_DIR="/tmp/cloudpc-runtime-$(id -u)"
install -d -m 700 "$XDG_RUNTIME_DIR"

# Create virtual audio device if needed
if ! pactl list short sinks |
    awk '$2=="cloudpc"{f=1} END{exit !f}'; then
    pactl load-module module-null-sink \
        sink_name=cloudpc \
        sink_properties=device.description=CloudPC-Audio \
        >/dev/null
fi

pactl set-default-sink cloudpc

# Redirect existing playback streams
pactl list short sink-inputs |
    awk '{print $1}' |
    while read -r id; do
        pactl move-sink-input "$id" cloudpc || true
    done

# Save environment for XFCE and Chrome
printf 'export PULSE_SERVER="%s"\nexport XDG_RUNTIME_DIR="%s"\n' \
    "$PULSE_SERVER" "$XDG_RUNTIME_DIR" \
    > "$DIR/audio-env.sh"

chmod 600 "$DIR/audio-env.sh"

# Start the new WebSocket server
if ! ss -ltnH | grep -Eq ':6081[[:space:]]'; then
    nohup "$VENV/bin/python" -u "$DIR/audio_ws.py" \
        > /tmp/cloudpc-audio.log 2>&1 < /dev/null &
    sleep 2
fi

# Verify the correct application is running
if ! curl -fsS --max-time 3 http://127.0.0.1:6081/ |
    grep -q "Cloud PC Low Latency Audio"; then
    echo "[ERROR] Audio WebSocket failed"
    tail -n 30 /tmp/cloudpc-audio.log || true
    exit 1
fi

echo "[AUDIO] WebSocket ready on port 6081"
echo "[AUDIO] Output: cloudpc"
