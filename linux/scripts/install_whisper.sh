#!/usr/bin/env bash
# First-run installer for whisper.cpp on Linux. Detects the host
# acceleration (CUDA → Vulkan → CPU) and pulls a matching pre-built
# binary plus the GGUF model into ~/.clawix/whisper/. Idempotent: a
# second run only re-downloads what's missing.
#
# The Tauri shell invokes this from `commands::install_whisper` when
# the user opens the dictation panel for the first time, but you can
# also run it directly:
#
#   bash clawix/linux/scripts/install_whisper.sh [--model large-v3-turbo|base.en|...]
#

set -euo pipefail

MODEL_NAME="${1:-large-v3-turbo}"
DEST="${HOME}/.clawix/whisper"
mkdir -p "$DEST"

detect_accel() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "cuda"
  elif command -v vulkaninfo >/dev/null 2>&1; then
    echo "vulkan"
  else
    echo "cpu"
  fi
}

ACCEL="$(detect_accel)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) echo "[whisper-install] unsupported arch: $ARCH" >&2; exit 78 ;;
esac

ASSET_BASE="https://github.com/ggerganov/whisper.cpp/releases/latest/download"
BIN_NAME="whisper-${ACCEL}-${ARCH}.tar.gz"
echo "[whisper-install] backend=$ACCEL arch=$ARCH model=$MODEL_NAME"

if [ ! -x "$DEST/whisper-cli" ]; then
  TMP="$(mktemp -t whisper.XXXXXX.tar.gz)"
  echo "[whisper-install] downloading binary…"
  curl -fsSL "$ASSET_BASE/$BIN_NAME" -o "$TMP" || {
    echo "[whisper-install] $BIN_NAME unavailable for this distro/release; falling back to CPU build"
    BIN_NAME="whisper-cpu-${ARCH}.tar.gz"
    curl -fsSL "$ASSET_BASE/$BIN_NAME" -o "$TMP"
  }
  tar -xzf "$TMP" -C "$DEST"
  chmod +x "$DEST/whisper-cli"
  rm -f "$TMP"
fi

MODEL_FILE="ggml-${MODEL_NAME}.bin"
MODEL_PATH="$DEST/$MODEL_FILE"
if [ ! -f "$MODEL_PATH" ]; then
  echo "[whisper-install] downloading model $MODEL_FILE…"
  curl -fsSL "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE" -o "$MODEL_PATH"
fi

echo "[whisper-install] ready → $DEST"
