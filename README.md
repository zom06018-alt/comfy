# RunPod ComfyUI + Anima embedded image

This project builds a Linux/AMD64 Docker image containing:

- ComfyUI
- Anima Base v1.0 diffusion model
- Qwen 0.6B text encoder
- Qwen Image VAE
- The custom-node repositories listed in `custom_nodes.txt`

The image uses `/opt/ComfyUI`, not `/workspace`. It therefore does not require a RunPod network volume or volume disk.

## Prerequisites

- Docker Desktop or Docker Engine with Buildx
- A Docker Hub/GHCR account with enough registry storage
- Sufficient local build cache and bandwidth; the resulting image is large

## Build and push

```bash
docker login
./build-and-push.sh docker.io/YOUR_NAME/comfyui-anima:v1
```

To build without pushing:

```bash
docker buildx build \
  --platform linux/amd64 \
  --progress=plain \
  -t comfyui-anima:v1 \
  --load .
```

`--load` may require substantial local disk space. Pushing directly is generally more practical for this model-heavy image.

## Run locally with NVIDIA Container Toolkit

```bash
docker run --rm --gpus all \
  -p 8188:8188 \
  comfyui-anima:v1
```

Open `http://localhost:8188`.

## RunPod template

Create a Pod template with these values:

- Container image: `docker.io/YOUR_NAME/comfyui-anima:v1`
- Container disk: start with 40 GB; increase if RunPod reports insufficient image/extraction space
- Volume disk: 0 GB
- Network volume: none
- HTTP port: `8188`
- Container start command: leave blank
- Optional environment variable: `COMFYUI_ARGS=--preview-method auto`

All runtime changes are ephemeral. Download generated images before stopping the Pod. To retain additional LoRAs, workflows, or custom nodes permanently, add them to this project and rebuild the image.

## Notes

- `ComfyUI-KJNodes` appeared twice in the supplied list and is included once.
- `chibi-client`, `comfyui-mobile-frontend`, and `honey_client` may behave as frontend/client projects rather than ordinary Python custom nodes. They are included exactly as requested. The build installs Python requirements and runs a root-level `install.py` when present.
- A dependency conflict intentionally fails the build instead of silently creating a broken image.
- For reproducible production builds, replace moving branches with commit hashes using explicit clone logic or a lock file.

## 추가 내장 모델

이미지 빌드 시 아래 파일도 자동으로 내려받아 `/opt/ComfyUI/models`에 포함합니다.

- `vae/Qwen2D_VAE.safetensors`
- `loras/anima-turbo-lora-v0.2.safetensors`
- `controlnet/anima-lllite-inpainting-v2.safetensors`

주의: 원래 전달된 Turbo LoRA 저장소명 `Anima-Off용-LoRAs`는 잘못된 주소이므로 공식 `Anima-Official-LoRAs`로 수정했습니다. LLLite 다운로드 원본 파일명도 `anima-lite-inpainting-v2.safetensors`가 아니라 `anima-lllite-inpainting-v2.safetensors`로 수정했습니다.

## Image Saver 및 실행 옵션

- `piexif`와 `ComfyUI-Image-Saver/requirements.txt`는 Docker 빌드 중 설치됩니다.
- 빌드 중 `import piexif` 검증이 실패하면 이미지 빌드가 중단됩니다.
- 컨테이너 시작 시 `libtcmalloc_minimal.so.4`가 존재할 때만 `LD_PRELOAD`에 적용됩니다.
- 기본 실행 옵션은 `--preview-method auto --fast --enable-cors-header`입니다.
- 다른 옵션을 사용하려면 RunPod 환경 변수 `COMFYUI_ARGS`로 덮어쓰십시오.
- Colab 전용 `/content`, `%cd`, `%env`, `newmain_2.py`는 사용하지 않으며 공식 `/opt/ComfyUI/main.py`를 실행합니다.
