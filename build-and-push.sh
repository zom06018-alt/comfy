#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-}"
if [[ -z "$IMAGE" ]]; then
  echo "Usage: $0 docker.io/USERNAME/comfyui-anima:TAG" >&2
  exit 2
fi

docker buildx inspect comfyui-anima-builder >/dev/null 2>&1 \
  || docker buildx create --name comfyui-anima-builder --use

docker buildx use comfyui-anima-builder
docker buildx build \
  --platform linux/amd64 \
  --progress=plain \
  --tag "$IMAGE" \
  --push \
  .
