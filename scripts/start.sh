#!/usr/bin/env bash

set -euo pipefail

COMFYUI_PATH="${COMFYUI_PATH:-/opt/ComfyUI}"

echo ""
echo "=============================================="
echo " RunPod ComfyUI + Anima"
echo "=============================================="
echo " ComfyUI    : 8188"
echo " JupyterLab : 8888"
echo " Root       : /opt"
echo "=============================================="
echo ""

# ============================================================
# tcmalloc
# ============================================================

TCMALLOC="$(find \
    /usr/lib \
    /usr/lib/x86_64-linux-gnu \
    -name 'libtcmalloc_minimal.so*' \
    2>/dev/null \
    | head -n 1 || true)"

if [[ -n "${TCMALLOC}" ]]; then

    echo "Using tcmalloc:"
    echo "${TCMALLOC}"

    export LD_PRELOAD="${TCMALLOC}"

else

    echo "tcmalloc not found."
    echo "Continuing without LD_PRELOAD."

fi

# ============================================================
# CUDA information
# ============================================================

python - <<'PY'
import torch

print("")
print("==============================================")
print("PyTorch :", torch.__version__)
print("CUDA    :", torch.version.cuda)

if torch.cuda.is_available():
    print("GPU     :", torch.cuda.get_device_name(0))
else:
    print("GPU     : CUDA NOT AVAILABLE")

print("==============================================")
print("")
PY

# ============================================================
# SageAttention check
# ============================================================

python - <<'PY'
try:
    from sageattention import sageattn
    print("SageAttention: OK")
except Exception as exc:
    print("SageAttention ERROR:")
    print(repr(exc))
PY

# ============================================================
# JupyterLab
# ============================================================

echo ""
echo "Starting JupyterLab on :8888"

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

echo "JupyterLab PID:"
echo "${JUPYTER_PID}"

# ============================================================
# Give Jupyter a moment to start
# ============================================================

sleep 2

if kill -0 "${JUPYTER_PID}" 2>/dev/null; then

    echo "JupyterLab: RUNNING"

else

    echo "WARNING: JupyterLab exited."

    if [[ -f /tmp/jupyter.log ]]; then
        cat /tmp/jupyter.log
    fi

fi

# ============================================================
# ComfyUI
# ============================================================

cd "${COMFYUI_PATH}"

echo ""
echo "Starting ComfyUI on :8188"
echo ""

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --preview-method auto \
    --fast \
    --enable-cors-header
