#!/bin/bash
# Push test models to Android device for integration tests.
# Usage: ./scripts/prepare_test_models.sh [device_id]
#
# Models are cached in ~/.cache/flutter_gemma/test_models/
# To download models there first, use scripts/download_test_models.sh
#
# Models are pushed to /data/local/tmp/flutter_gemma_test/ on device.

set -e

CACHE_DIR="$HOME/.cache/flutter_gemma/test_models"
DEVICE_DIR="/data/local/tmp/flutter_gemma_test"
DEVICE_ID="${1:-}"

if [ ! -d "$CACHE_DIR" ]; then
  echo "ERROR: Cache dir not found: $CACHE_DIR"
  echo "Download models first with: ./scripts/download_test_models.sh"
  exit 1
fi

ADB_ARGS=""
if [ -n "$DEVICE_ID" ]; then
  ADB_ARGS="-s $DEVICE_ID"
fi

# Check device connected
if ! adb $ADB_ARGS shell echo ok > /dev/null 2>&1; then
  echo "ERROR: No Android device connected"
  [ -n "$DEVICE_ID" ] && echo "Device ID: $DEVICE_ID"
  exit 1
fi

adb $ADB_ARGS shell mkdir -p "$DEVICE_DIR"

INFERENCE_MODELS=(
  "functiongemma-270M-it.task"
  "gemma3-1b-it-int4.task"
  "Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task"
  "deepseek_q8_ekv1280.task"
  "gemma-3n-E2B-it-int4.task"
)

pushed=0
for model in "${INFERENCE_MODELS[@]}"; do
  src="$CACHE_DIR/$model"
  if [ -f "$src" ]; then
    # Check if already on device (by size)
    local_size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src")
    remote_size=$(adb $ADB_ARGS shell stat -c%s "$DEVICE_DIR/$model" 2>/dev/null || echo "0")
    remote_size=$(echo "$remote_size" | tr -d '\r')

    if [ "$local_size" = "$remote_size" ]; then
      echo "SKIP (already on device): $model"
    else
      echo "PUSH: $model ($(du -h "$src" | cut -f1))"
      adb $ADB_ARGS push "$src" "$DEVICE_DIR/$model"
      ((pushed++))
    fi
  else
    echo "MISS: $model (not in cache)"
  fi
done

echo ""
echo "Done. Pushed $pushed model(s) to $DEVICE_DIR"
echo "Embedding models (tflite, tokenizers) are in app assets — no push needed."
