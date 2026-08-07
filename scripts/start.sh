#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/ComfyUI

# Use tcmalloc when the base image provides it. Unlike Colab LD_PRELOAD magic,
# this is applied safely at container startup.
TCMALLOC="/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4"
if [[ -f "$TCMALLOC" ]]; then
  export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}$TCMALLOC"
fi

# Sensible defaults matching the supplied notebook launch flags.
# Override entirely through COMFYUI_ARGS in the RunPod template when needed.
DEFAULT_ARGS="--preview-method auto --fast --enable-cors-header"
read -r -a EXTRA_ARGS <<< "${COMFYUI_ARGS:-$DEFAULT_ARGS}"

exec python main.py --listen 0.0.0.0 --port 8188 "${EXTRA_ARGS[@]}"
