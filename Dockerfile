# syntax=docker/dockerfile:1.7
ARG ANIMA_REVISION=main
ENV ANIMA_REVISION=${ANIMA_REVISION}
ARG BASE_IMAGE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG COMFYUI_REF=master
ARG ANIMA_REVISION=main

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFYUI_PATH=/opt/ComfyUI \
    HF_HOME=/opt/huggingface-cache

RUN apt-get update && apt-get install -y --no-install-recommends \
      aria2 ca-certificates curl ffmpeg git git-lfs libgl1 libglib2.0-0 \
      libtcmalloc-minimal4t64 build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 --branch "${COMFYUI_REF}" https://github.com/Comfy-Org/ComfyUI.git ComfyUI

WORKDIR /opt/ComfyUI
RUN python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY custom_nodes.txt /tmp/custom_nodes.txt
COPY scripts/install-custom-nodes.sh /usr/local/bin/install-custom-nodes
RUN chmod +x /usr/local/bin/install-custom-nodes \
    && /usr/local/bin/install-custom-nodes /tmp/custom_nodes.txt /opt/ComfyUI/custom_nodes \
    && rm -f /tmp/custom_nodes.txt

# Image Saver requires piexif. Install it explicitly before runtime and
# reinstall the node's declared requirements so startup never performs pip work.
RUN python -m pip install --no-cache-dir piexif \
    && python -m pip install --no-cache-dir \
       -r /opt/ComfyUI/custom_nodes/ComfyUI-Image-Saver/requirements.txt \
    && python -c "import piexif; print('piexif OK:', piexif.__file__)"

RUN mkdir -p \
      models/diffusion_models \
      models/text_encoders \
      models/vae \
      models/loras \
      models/controlnet \
      models/upscale_models \
      models/ultralytics \
      input output user/default/workflows

# Hugging Face Xet-compatible downloader
RUN python -m pip install --no-cache-dir --upgrade \
    "huggingface_hub[hf_xet]"

ENV HF_HOME=/tmp/huggingface

RUN python - <<'PY'
from pathlib import Path
from huggingface_hub import hf_hub_download
import os
import shutil

anima_revision = os.environ.get("ANIMA_REVISION", "main")

files = [
    {
        "repo_id": "circlestone-labs/Anima",
        "filename": "split_files/diffusion_models/anima-base-v1.0.safetensors",
        "revision": anima_revision,
        "destination": "/opt/ComfyUI/models/diffusion_models/anima-base-v1.0.safetensors",
    },
    {
        "repo_id": "circlestone-labs/Anima",
        "filename": "split_files/text_encoders/qwen_3_06b_base.safetensors",
        "revision": anima_revision,
        "destination": "/opt/ComfyUI/models/text_encoders/qwen_3_06b_base.safetensors",
    },
    {
        "repo_id": "circlestone-labs/Anima",
        "filename": "split_files/vae/qwen_image_vae.safetensors",
        "revision": anima_revision,
        "destination": "/opt/ComfyUI/models/vae/qwen_image_vae.safetensors",
    },
    {
        "repo_id": "Anzhc/Qwen2D-VAE",
        "filename": "Qwen2D_VAE.safetensors",
        "revision": "main",
        "destination": "/opt/ComfyUI/models/vae/Qwen2D_VAE.safetensors",
    },
    {
        "repo_id": "circlestone-labs/Anima-Official-LoRAs",
        "filename": "anima-turbo-lora-v0.2.safetensors",
        "revision": "main",
        "destination": "/opt/ComfyUI/models/loras/anima-turbo-lora-v0.2.safetensors",
    },
    {
        "repo_id": "kohya-ss/Anima-LLLite",
        "filename": "anima-lllite-inpainting-v2.safetensors",
        "revision": "main",
        "destination": "/opt/ComfyUI/models/controlnet/anima-lllite-inpainting-v2.safetensors",
    },
]

for item in files:
    destination = Path(item["destination"])
    destination.parent.mkdir(parents=True, exist_ok=True)

    print(
        f"Downloading {item['repo_id']}/"
        f"{item['filename']}@{item['revision']}"
    )

    cached_path = hf_hub_download(
        repo_id=item["repo_id"],
        filename=item["filename"],
        revision=item["revision"],
    )

    shutil.copyfile(cached_path, destination)

    size = destination.stat().st_size
    if size <= 0:
        raise RuntimeError(f"Downloaded file is empty: {destination}")

    print(f"Saved {destination}: {size:,} bytes")

print("All model downloads completed.")
PY

RUN rm -rf /tmp/huggingface

# Remove caches and Git histories after installation to reduce image size.
RUN find /opt/ComfyUI/custom_nodes -type d -name .git -prune -exec rm -rf '{}' + \
    && rm -rf /root/.cache /opt/huggingface-cache /tmp/*

COPY scripts/start.sh /usr/local/bin/start-comfyui
RUN chmod +x /usr/local/bin/start-comfyui

WORKDIR /opt/ComfyUI
EXPOSE 8188

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8188/system_stats >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/start-comfyui"]
