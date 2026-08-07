# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG COMFYUI_REF=master
ARG ANIMA_REVISION=main

ENV ANIMA_REVISION=${ANIMA_REVISION} \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFYUI_PATH=/opt/ComfyUI \
    HF_HOME=/opt/huggingface-cache

# ------------------------------------------------------------
# System packages
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        git-lfs \
        wget \
        libgl1 \
        libglib2.0-0 \
        libtcmalloc-minimal4t64 \
        build-essential \
        pkg-config \
        ninja-build \
    && rm -rf /var/lib/apt/lists/*

RUN git lfs install

# ------------------------------------------------------------
# ComfyUI
# ------------------------------------------------------------

WORKDIR /opt

RUN git clone https://github.com/Comfy-Org/ComfyUI.git \
    && cd ComfyUI \
    && git checkout "${COMFYUI_REF}"

WORKDIR /opt/ComfyUI

RUN python -m pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------
# JupyterLab + common packages
# ------------------------------------------------------------

RUN python -m pip install --no-cache-dir \
    jupyterlab \
    piexif

# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------

WORKDIR /opt/ComfyUI/custom_nodes

RUN set -eux; \
    git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git; \
    git clone --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git; \
    git clone --depth 1 https://github.com/bedovyy/chibi-client.git; \
    git clone --depth 1 https://github.com/cosmicbuffalo/comfyui-mobile-frontend.git; \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git; \
    git clone --depth 1 https://github.com/ruwwww/comfyui-spectrum-sdxl.git; \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git; \
    git clone --depth 1 https://github.com/BobJohnson24/ComfyUI-INT8-Fast.git; \
    git clone --depth 1 https://github.com/Anzhc/anzhc-qwen2d-comfyui.git; \
    git clone --depth 1 https://github.com/arcacolab/honey_client.git; \
    git clone --depth 1 https://github.com/kohya-ss/ComfyUI-Anima-LLLite.git; \
    git clone --depth 1 https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git; \
    git clone --depth 1 https://github.com/n0va39/ComfyUI-EasyUseAnima.git; \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git; \
    git clone --depth 1 https://github.com/alexopus/ComfyUI-Image-Saver.git; \
    git clone --depth 1 https://github.com/willmiao/ComfyUI-Lora-Manager.git

# ------------------------------------------------------------
# Custom node dependencies
# ------------------------------------------------------------

RUN set -eux; \
    while IFS= read -r req; do \
        echo "Installing ${req}"; \
        python -m pip install --no-cache-dir -r "${req}"; \
    done < <(find /opt/ComfyUI/custom_nodes \
        -mindepth 2 \
        -maxdepth 2 \
        -type f \
        -name requirements.txt \
        | sort)

# ------------------------------------------------------------
# Image Saver dependencies
# ------------------------------------------------------------

RUN python -m pip install --no-cache-dir piexif \
    && python -m pip install --no-cache-dir \
       -r /opt/ComfyUI/custom_nodes/ComfyUI-Image-Saver/requirements.txt \
    && python -c "import piexif; print('piexif OK:', piexif.__file__)"

# ------------------------------------------------------------
# SageAttention
# EasyUseAnima -> KJNodes requires this
# ------------------------------------------------------------

RUN python -m pip install --no-cache-dir sageattention \
    && python -c "from sageattention import sageattn; print('SageAttention OK')"

# ------------------------------------------------------------
# Model directories
# ------------------------------------------------------------

WORKDIR /opt/ComfyUI

RUN mkdir -p \
    models/checkpoints \
    models/diffusion_models \
    models/text_encoders \
    models/vae \
    models/loras \
    models/controlnet \
    models/upscale_models \
    models/embeddings \
    input \
    output \
    user/default/workflows

# ------------------------------------------------------------
# Hugging Face downloader
# ------------------------------------------------------------

RUN python -m pip install --no-cache-dir --upgrade \
    "huggingface_hub[hf_xet]"

# ------------------------------------------------------------
# Download embedded models
# ------------------------------------------------------------

RUN python - <<'PY'
from pathlib import Path
from huggingface_hub import hf_hub_download
import os
import shutil

anima_revision = os.environ.get("ANIMA_REVISION", "main")

files = [
    (
        "circlestone-labs/Anima",
        "split_files/diffusion_models/anima-base-v1.0.safetensors",
        anima_revision,
        "/opt/ComfyUI/models/diffusion_models/anima-base-v1.0.safetensors",
    ),
    (
        "circlestone-labs/Anima",
        "split_files/text_encoders/qwen_3_06b_base.safetensors",
        anima_revision,
        "/opt/ComfyUI/models/text_encoders/qwen_3_06b_base.safetensors",
    ),
    (
        "circlestone-labs/Anima",
        "split_files/vae/qwen_image_vae.safetensors",
        anima_revision,
        "/opt/ComfyUI/models/vae/qwen_image_vae.safetensors",
    ),
    (
        "Anzhc/Qwen2D-VAE",
        "Qwen2D_VAE.safetensors",
        "main",
        "/opt/ComfyUI/models/vae/Qwen2D_VAE.safetensors",
    ),
    (
        "circlestone-labs/Anima-Official-LoRAs",
        "anima-turbo-lora-v0.2.safetensors",
        "main",
        "/opt/ComfyUI/models/loras/anima-turbo-lora-v0.2.safetensors",
    ),
    (
        "kohya-ss/Anima-LLLite",
        "anima-lllite-inpainting-v2.safetensors",
        "main",
        "/opt/ComfyUI/models/controlnet/anima-lllite-inpainting-v2.safetensors",
    ),
]

for repo_id, filename, revision, destination in files:
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)

    print(f"Downloading: {repo_id}/{filename}")

    cached_file = hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        revision=revision,
    )

    shutil.copyfile(cached_file, destination)

    size = destination.stat().st_size
    if size <= 0:
        raise RuntimeError(f"Empty file: {destination}")

    print(f"OK: {destination} ({size:,} bytes)")

print("ALL MODELS DOWNLOADED")
PY

# Remove temporary Hugging Face cache
RUN rm -rf /opt/huggingface-cache

# ------------------------------------------------------------
# Final validation
# ------------------------------------------------------------

RUN python - <<'PY'
import torch
import piexif
from sageattention import sageattn

print("===================================")
print("PyTorch:", torch.__version__)
print("CUDA:", torch.version.cuda)
print("piexif: OK")
print("SageAttention: OK")
print("===================================")
PY

# ------------------------------------------------------------
# Startup
# ------------------------------------------------------------

COPY start.sh /usr/local/bin/start-comfy

RUN chmod +x /usr/local/bin/start-comfy

EXPOSE 8188 8888

WORKDIR /opt/ComfyUI

CMD ["/usr/local/bin/start-comfy"]
