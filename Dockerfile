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

# ============================================================
# System packages
# ============================================================

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
        zip \
        unzip \
        rsync \
    && rm -rf /var/lib/apt/lists/*

RUN git lfs install

# ============================================================
# Upgrade Python build tools
# ============================================================

RUN python -m pip install --no-cache-dir --upgrade \
    pip \
    setuptools \
    wheel \
    ninja

# ============================================================
# ComfyUI
# ============================================================

WORKDIR /opt

RUN git clone https://github.com/Comfy-Org/ComfyUI.git \
    && cd /opt/ComfyUI \
    && git checkout "${COMFYUI_REF}"

WORKDIR /opt/ComfyUI

RUN python -m pip install --no-cache-dir \
    -r requirements.txt

# ============================================================
# JupyterLab
# ============================================================

RUN python -m pip install --no-cache-dir \
    jupyterlab \
    piexif \
    gdown

# ============================================================
# Custom Nodes
# ============================================================

WORKDIR /opt/ComfyUI/custom_nodes

RUN set -eux; \
    git clone --depth 1 \
        https://github.com/Comfy-Org/ComfyUI-Manager.git; \
    \
    git clone --depth 1 \
        https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git; \
    \
    git clone --depth 1 \
        https://github.com/bedovyy/chibi-client.git; \
    \
    git clone --depth 1 \
        https://github.com/cosmicbuffalo/comfyui-mobile-frontend.git; \
    \
    git clone --depth 1 \
        https://github.com/rgthree/rgthree-comfy.git; \
    \
    git clone --depth 1 \
        https://github.com/ruwwww/comfyui-spectrum-sdxl.git; \
    \
    git clone --depth 1 \
        https://github.com/kijai/ComfyUI-KJNodes.git; \
    \
    git clone --depth 1 \
        https://github.com/BobJohnson24/ComfyUI-INT8-Fast.git; \
    \
    git clone --depth 1 \
        https://github.com/Anzhc/anzhc-qwen2d-comfyui.git; \
    \
    git clone --depth 1 \
        https://github.com/arcacolab/honey_client.git; \
    \
    git clone --depth 1 \
        https://github.com/kohya-ss/ComfyUI-Anima-LLLite.git; \
    \
    git clone --depth 1 \
        https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git; \
    \
    git clone --depth 1 \
        https://github.com/n0va39/ComfyUI-EasyUseAnima.git; \
    \
    git clone --depth 1 \
        https://github.com/ltdrdata/ComfyUI-Impact-Pack.git; \
    \
    git clone --depth 1 \
        https://github.com/alexopus/ComfyUI-Image-Saver.git; \
    \
    git clone --depth 1 \
        https://github.com/willmiao/ComfyUI-Lora-Manager.git

# ============================================================
# Install Custom Node requirements
#
# 실패하면 어느 requirements.txt가 범인인지 정확히 출력
# ============================================================

RUN set -eu; \
    \
    find /opt/ComfyUI/custom_nodes \
        -mindepth 2 \
        -maxdepth 2 \
        -type f \
        -name requirements.txt \
        | sort \
        > /tmp/custom_node_requirements.txt; \
    \
    echo ""; \
    echo "============================================"; \
    echo "CUSTOM NODE REQUIREMENTS"; \
    echo "============================================"; \
    cat /tmp/custom_node_requirements.txt || true; \
    echo "============================================"; \
    \
    while IFS= read -r req; do \
        [ -n "${req}" ] || continue; \
        \
        echo ""; \
        echo "============================================"; \
        echo "INSTALLING:"; \
        echo "${req}"; \
        echo "============================================"; \
        \
        if ! python -m pip install \
            --no-cache-dir \
            --prefer-binary \
            -r "${req}"; then \
            \
            echo ""; \
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
            echo "CUSTOM NODE REQUIREMENTS FAILED"; \
            echo "FILE:"; \
            echo "${req}"; \
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
            \
            exit 1; \
        fi; \
    done < /tmp/custom_node_requirements.txt; \
    \
    rm -f /tmp/custom_node_requirements.txt

# ============================================================
# Image Saver dependency check
# ============================================================

RUN python -m pip install --no-cache-dir piexif \
    && python -c "import piexif; print('piexif OK:', piexif.__file__)"

# ============================================================
# SageAttention
#
# EasyUseAnima -> KJNodes requires:
# from sageattention import sageattn
# ============================================================

RUN python -m pip install --no-cache-dir sageattention \
    && python -c "from sageattention import sageattn; print('SageAttention OK')"

# ============================================================
# ComfyUI model directories
# ============================================================

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
    models/clip \
    input \
    output \
    temp \
    user/default/workflows

# ============================================================
# Hugging Face downloader
# ============================================================

RUN python -m pip install --no-cache-dir --upgrade \
    "huggingface_hub[hf_xet]"

# ============================================================
# Download Anima models into Docker image
# ============================================================

RUN python - <<'PY'
from pathlib import Path
from huggingface_hub import hf_hub_download

import os
import shutil


anima_revision = os.environ.get(
    "ANIMA_REVISION",
    "main",
)

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

    destination = Path(
        item["destination"]
    )

    destination.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    print("")
    print("==========================================")
    print("Downloading:")
    print(item["repo_id"])
    print(item["filename"])
    print("==========================================")

    cached_file = hf_hub_download(
        repo_id=item["repo_id"],
        filename=item["filename"],
        revision=item["revision"],
    )

    shutil.copyfile(
        cached_file,
        destination,
    )

    size = destination.stat().st_size

    if size <= 0:
        raise RuntimeError(
            f"Downloaded file is empty: {destination}"
        )

    print(
        f"OK: {destination} "
        f"({size:,} bytes)"
    )


print("")
print("==========================================")
print("ALL MODELS DOWNLOADED")
print("==========================================")
PY

# ============================================================
# Remove Hugging Face build cache
#
# 모델 원본은 /opt/ComfyUI/models 아래 있으므로
# HF 캐시는 이미지에서 제거
# ============================================================

RUN rm -rf /opt/huggingface-cache

# ============================================================
# Remove .git directories from Custom Nodes
#
# Docker image 용량을 조금 줄임
# ============================================================

RUN find /opt/ComfyUI/custom_nodes \
    -mindepth 2 \
    -maxdepth 2 \
    -type d \
    -name .git \
    -prune \
    -exec rm -rf {} +

# ============================================================
# Final validation
# ============================================================

WORKDIR /opt/ComfyUI

RUN python - <<'PY'
import torch
import piexif

print("")
print("==========================================")
print("FINAL BUILD VALIDATION")
print("==========================================")

print("PyTorch:")
print(torch.__version__)

print("CUDA:")
print(torch.version.cuda)

print("piexif:")
print(piexif.__file__)

from sageattention import sageattn

print("SageAttention:")
print("OK")

print("==========================================")
PY

# ============================================================
# Startup script
#
# 중요:
# scripts/start.sh를 맨 마지막에 COPY
# start.sh만 변경할 때 앞쪽 모델 레이어 캐시 유지 가능
# ============================================================

COPY scripts/start.sh /usr/local/bin/start-comfy

RUN chmod +x /usr/local/bin/start-comfy

EXPOSE 8188 8888

WORKDIR /opt/ComfyUI

CMD ["/usr/local/bin/start-comfy"]
