# syntax=docker/dockerfile:1.7
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

# Models are embedded in the image. No /workspace volume is required.
RUN aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/diffusion_models \
      -o anima-base-v1.0.safetensors \
      "https://huggingface.co/circlestone-labs/Anima/resolve/${ANIMA_REVISION}/split_files/diffusion_models/anima-base-v1.0.safetensors?download=true" \
    && aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/text_encoders \
      -o qwen_3_06b_base.safetensors \
      "https://huggingface.co/circlestone-labs/Anima/resolve/${ANIMA_REVISION}/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
    && aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/vae \
      -o qwen_image_vae.safetensors \
      "https://huggingface.co/circlestone-labs/Anima/resolve/${ANIMA_REVISION}/split_files/vae/qwen_image_vae.safetensors?download=true" \
    && aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/vae \
      -o Qwen2D_VAE.safetensors \
      "https://huggingface.co/Anzhc/Qwen2D-VAE/resolve/main/Qwen2D_VAE.safetensors?download=true" \
    && aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/loras \
      -o anima-turbo-lora-v0.2.safetensors \
      "https://huggingface.co/circlestone-labs/Anima-Official-LoRAs/resolve/main/anima-turbo-lora-v0.2.safetensors?download=true" \
    && aria2c --console-log-level=warn --summary-interval=10 \
      --allow-overwrite=true --auto-file-renaming=false \
      --max-connection-per-server=8 --split=8 --min-split-size=10M \
      -d models/controlnet \
      -o anima-lllite-inpainting-v2.safetensors \
      "https://huggingface.co/kohya-ss/Anima-LLLite/resolve/main/anima-lllite-inpainting-v2.safetensors?download=true" \
    && test -s models/diffusion_models/anima-base-v1.0.safetensors \
    && test -s models/text_encoders/qwen_3_06b_base.safetensors \
    && test -s models/vae/qwen_image_vae.safetensors \
    && test -s models/vae/Qwen2D_VAE.safetensors \
    && test -s models/loras/anima-turbo-lora-v0.2.safetensors \
    && test -s models/controlnet/anima-lllite-inpainting-v2.safetensors

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
