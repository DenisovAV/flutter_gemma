#!/usr/bin/env bash
# Download EmbeddingGemma ONNX model for onnx_embedding_test.dart
#
# Model: onnx-community/embeddinggemma-300m-ONNX (int8 quantized)
# Files: model_quantized.onnx (~555 KB graph)
#        model_quantized.onnx_data (~295 MB weights)
#        tokenizer.model (~4.5 MB SentencePiece vocab)
#
# Usage:
#   ./scripts/download_onnx_embedding_model.sh             # macOS (default)
#   ./scripts/download_onnx_embedding_model.sh --platform linux
#   ./scripts/download_onnx_embedding_model.sh --platform android
#   ./scripts/download_onnx_embedding_model.sh --dir /custom/path
#
# After download, run:
#   flutter test integration_test/onnx_embedding_test.dart -d macos
set -euo pipefail

HF_BASE="https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX/resolve/main"
MODEL_GRAPH="model_quantized.onnx"
MODEL_DATA="model_quantized.onnx_data"
TOKENIZER="tokenizer.model"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PLATFORM="${1:-auto}"
CUSTOM_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --dir)      CUSTOM_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve destination directory
# ---------------------------------------------------------------------------
if [[ -n "$CUSTOM_DIR" ]]; then
  DEST="$CUSTOM_DIR"
elif [[ "$PLATFORM" == "auto" ]]; then
  case "$(uname -s)" in
    Darwin)
      # macOS sandbox: Application Support / flutter_gemma inside the example app container.
      BUNDLE_ID="dev.flutterberlin.flutterGemmaExample55"
      DEST="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/$BUNDLE_ID/flutter_gemma"
      ;;
    Linux)
      DEST="$HOME/models"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      DEST="${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/flutter_gemma"
      ;;
    *)
      echo "Unknown platform. Use --dir to specify destination." >&2
      exit 1
      ;;
  esac
else
  case "$PLATFORM" in
    macos)
      BUNDLE_ID="dev.flutterberlin.flutterGemmaExample55"
      DEST="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/$BUNDLE_ID/flutter_gemma"
      ;;
    linux)
      DEST="$HOME/models"
      ;;
    android)
      DEST="/data/local/tmp/flutter_gemma_test"
      echo "NOTE: Android path requires adb push. Run:"
      echo "  adb push <file> $DEST/"
      echo "Download to current directory instead:"
      DEST="$(pwd)/onnx_models"
      ;;
    windows)
      DEST="${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/flutter_gemma"
      ;;
    *)
      echo "Unknown platform: $PLATFORM. Use --dir to specify destination." >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$DEST"
echo "Destination: $DEST"

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_if_missing() {
  local filename="$1"
  local url="$2"
  local dest="$DEST/$filename"
  if [[ -f "$dest" ]]; then
    echo "  Already exists: $filename ($(du -sh "$dest" | cut -f1))"
  else
    echo "  Downloading $filename..."
    curl -L --progress-bar -o "$dest" "$url"
    echo "  Done: $(du -sh "$dest" | cut -f1)"
  fi
}

download_if_missing "$MODEL_GRAPH"  "$HF_BASE/onnx/$MODEL_GRAPH"
download_if_missing "$MODEL_DATA"   "$HF_BASE/onnx/$MODEL_DATA"
download_if_missing "$TOKENIZER"    "$HF_BASE/$TOKENIZER"

echo ""
echo "All files ready in: $DEST"
echo ""
echo "Run the integration test:"
echo "  cd packages/flutter_gemma/example"
echo "  flutter test integration_test/onnx_embedding_test.dart -d macos"
