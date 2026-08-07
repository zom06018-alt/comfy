#!/usr/bin/env bash

set -euo pipefail

COMFYUI_PATH="${COMFYUI_PATH:-/opt/ComfyUI}"

echo "========================================"
echo " Starting RunPod ComfyUI + JupyterLab"
echo "========================================"

# ------------------------------------------------------------
# tcmalloc
# ------------------------------------------------------------

TCMALLOC="$(find /usr/lib /usr/lib/x86_64-linux-gnu \
    -name 'libtcmalloc_minimal.so*' \
    2>/dev/null \
    | head -n 1 || true)"

if [[ -n "${TCMALLOC}" ]]; then
    echo "Using tcmalloc: ${TCMALLOC}"
    export LD_PRELOAD="${TCMALLOC}"
else
    echo "tcmalloc library not found; continuing without LD_PRELOAD."
fi

# ------------------------------------------------------------
# SageAttention check
# ------------------------------------------------------------

python - <<'PY'
try:
    from sageattention import sageattn
    print("SageAttention: OK")
except Exception as exc:
    print("WARNING: SageAttention unavailable:", repr(exc))
PY

# ------------------------------------------------------------
# JupyterLab
# ------------------------------------------------------------

echo "Starting JupyterLab on port 8888..."

jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --allow-root \
    --ServerApp.token='' \
    --ServerApp.password='' \
    --ServerApp.allow_origin='*' \
    --ServerApp.root_dir=/opt \
    > /tmp/jupyter.log 2>&1 &

JUPYTER_PID=$!

echo "JupyterLab PID: ${JUPYTER_PID}"

# ------------------------------------------------------------
# ComfyUI
# ------------------------------------------------------------

cd "${COMFYUI_PATH}"

echo "Starting ComfyUI on port 8188..."

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --preview-method auto \
    --fast \
    --enable-cors-header
