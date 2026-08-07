#!/usr/bin/env bash
set -Eeuo pipefail

LIST_FILE="${1:?custom node list is required}"
DEST="${2:?destination directory is required}"
mkdir -p "$DEST"
CURRENT_REPO="(not started)"
CURRENT_STEP="initialization"

on_error() {
  code=$?
  echo >&2
  echo "============================================================" >&2
  echo "CUSTOM NODE INSTALL FAILED" >&2
  echo "Repository: ${CURRENT_REPO}" >&2
  echo "Step:       ${CURRENT_STEP}" >&2
  echo "Exit code:  ${code}" >&2
  echo "============================================================" >&2
  exit "$code"
}
trap on_error ERR

while IFS= read -r repo || [[ -n "$repo" ]]; do
  repo="${repo%%#*}"
  repo="$(printf '%s' "$repo" | xargs)"
  [[ -z "$repo" ]] && continue

  CURRENT_REPO="$repo"
  name="$(basename "$repo" .git)"
  target="$DEST/$name"

  CURRENT_STEP="git clone"
  echo ":: cloning $repo"
  for attempt in 1 2 3; do
    if git clone --depth 1 --filter=blob:none "$repo" "$target"; then
      break
    fi
    rm -rf "$target"
    if [[ "$attempt" == 3 ]]; then
      echo ":: clone failed after 3 attempts: $repo" >&2
      false
    fi
    echo ":: clone attempt $attempt failed; retrying..." >&2
    sleep $((attempt * 3))
  done

  # Only install requirements files near the repository root. Some frontend
  # projects contain unrelated nested examples with their own requirements.
  CURRENT_STEP="requirements installation"
  while IFS= read -r -d '' req; do
    echo ":: installing $req"
    python -m pip install --no-cache-dir -r "$req"
  done < <(find "$target" -maxdepth 2 -type f -iname 'requirements.txt' -print0 | sort -z)

  CURRENT_STEP="install.py"
  if [[ -f "$target/install.py" ]]; then
    echo ":: running $target/install.py"
    (cd "$target" && python install.py)
  fi

done < "$LIST_FILE"

trap - ERR
CURRENT_REPO="all custom nodes"
CURRENT_STEP="pip dependency audit"
# Base CUDA/RunPod images may contain unrelated package metadata conflicts.
# Report them, but do not discard an otherwise working ComfyUI image.
if ! python -m pip check; then
  echo ":: WARNING: pip check reported dependency conflicts." >&2
  echo ":: The image build will continue; verify ComfyUI startup logs." >&2
fi
