#!/bin/bash
# Build libLiteRtDispatch_Qualcomm.so for Android arm64 from LiteRT source.
#
# Requires the Qualcomm QNN dispatch bridge between LiteRT-LM and the on-device
# QNN/HTP runtime. This lib is NOT shipped in official LiteRT releases as of
# LiteRT v2.1.5 — we build it from source.
#
# Prerequisites:
#   - Bazel (via bazelisk): brew install bazelisk
#   - Android NDK at ~/Library/Android/sdk/ndk/<version>/
#   - Internet access (Bazel auto-downloads QAIRT SDK ~500MB on first run)
#     OR set LITERT_QAIRT_SDK=/path/to/qairt/2.44.0.260225 to use local copy
#
# Usage:
#   ./build_qualcomm_dispatch.sh
#   LITERT_QAIRT_SDK=/path/to/qairt/2.44.0.260225 ./build_qualcomm_dispatch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREBUILT_DIR="$SCRIPT_DIR/prebuilt/android_arm64"
LITERT_DIR="/tmp/LiteRT"

# The dispatch library must be built from the SAME LiteRT tree as the engine it
# calls into. Hardcoding a ref here is how it silently drifted: this file sat at
# 5c5b9ce6 (LiteRT-LM ffed38ad, native-v0.12.0) while the engine moved on, and a
# stale dispatch does not fail politely — on v0.16.0 it SIGSEGVs inside
# LiteRtDestroyOptions the moment engine_create tears an options object down.
#
# So derive it instead: read LITERT_REF out of the WORKSPACE of the LiteRT-LM
# revision we are building. Pass LITERTLM_REF to match a specific engine build.
#
# Do NOT go back to a literal, and do NOT use LiteRT v2.1.1 or earlier — the
# LiteRtDispatchApi struct has breaking ABI changes after it.
LITERTLM_REF="${LITERTLM_REF:-924e79c91542761242244e4f1651851f822e4cbb}"   # v0.16.0
LITERT_REF="${LITERT_REF:-}"
if [ -z "$LITERT_REF" ]; then
  echo "Resolving LITERT_REF from LiteRT-LM $LITERTLM_REF WORKSPACE..."
  LITERT_REF="$(curl -fsSL \
    "https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/$LITERTLM_REF/WORKSPACE" \
    | sed -n 's/^LITERT_REF *= *"\([0-9a-f]*\)".*/\1/p' | head -1)"
  if [ -z "$LITERT_REF" ]; then
    echo "ERROR: could not read LITERT_REF from LiteRT-LM $LITERTLM_REF" >&2
    exit 1
  fi
  echo "  -> $LITERT_REF"
fi

# Resolve Android NDK
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/$(ls -1 "$HOME/Library/Android/sdk/ndk" | sort -V | tail -1)"
    export ANDROID_NDK_HOME
    echo "Auto-detected ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
  else
    echo "ERROR: ANDROID_NDK_HOME not set and ~/Library/Android/sdk/ndk not found"
    exit 1
  fi
fi

if [ -z "${ANDROID_HOME:-}" ]; then
  export ANDROID_HOME="$(dirname "$(dirname "$ANDROID_NDK_HOME")")"
  echo "Auto-detected ANDROID_HOME=$ANDROID_HOME"
fi

echo "=== Building libLiteRtDispatch_Qualcomm.so for Android arm64 ==="
echo "LiteRT ref:         $LITERT_REF"
echo "ANDROID_NDK_HOME:   $ANDROID_NDK_HOME"
echo "ANDROID_HOME:       $ANDROID_HOME"
if [ -n "${LITERT_QAIRT_SDK:-}" ]; then
  echo "LITERT_QAIRT_SDK:   $LITERT_QAIRT_SDK (local)"
else
  echo "LITERT_QAIRT_SDK:   (Bazel will auto-download QAIRT 2.44.0.260225 ~500MB)"
fi

# 1. Clone or update LiteRT
if [ -d "$LITERT_DIR/.git" ]; then
  echo ""
  echo "Updating $LITERT_DIR..."
  git -C "$LITERT_DIR" fetch origin
else
  echo ""
  echo "Cloning LiteRT..."
  git clone https://github.com/google-ai-edge/LiteRT "$LITERT_DIR"
fi

echo "Checking out $LITERT_REF..."
git -C "$LITERT_DIR" checkout -f "$LITERT_REF"
echo "Building from: $(git -C "$LITERT_DIR" log --oneline -1)"

cd "$LITERT_DIR"

# 2. Write .litert_configure.bazelrc with Android NDK path.
# LiteRT's .bazelrc does `try-import %workspace%/.litert_configure.bazelrc` —
# without it //external:android/crosstool doesn't exist and arm64-v8a build fails.
NDK_API_LEVEL=30
echo "Generating .litert_configure.bazelrc (NDK=$ANDROID_NDK_HOME, API=$NDK_API_LEVEL)..."
cat > "$LITERT_DIR/.litert_configure.bazelrc" <<EOF
build --action_env ANDROID_NDK_HOME="$ANDROID_NDK_HOME"
build --action_env ANDROID_NDK_API_LEVEL="$NDK_API_LEVEL"
build --action_env ANDROID_SDK_HOME="$ANDROID_HOME"
build --action_env ANDROID_SDK_API_LEVEL="34"
build --action_env ANDROID_BUILD_TOOLS_VERSION="34.0.0"
EOF

# 3. Build dispatch lib
echo ""
echo "=== Running Bazel build ==="
bazelisk build \
  --repo_env=HERMETIC_PYTHON_VERSION=3.12 \
  --config=android_arm64 \
  --compilation_mode=opt \
  --strip=always \
  --linkopt=-Wl,-z,max-page-size=16384 \
  //litert/vendors/qualcomm/dispatch:dispatch_api_so

# 4. Copy to prebuilt dir
mkdir -p "$PREBUILT_DIR"
OUTPUT="bazel-bin/litert/vendors/qualcomm/dispatch/libLiteRtDispatch_Qualcomm.so"
if [ ! -f "$OUTPUT" ]; then
  echo "ERROR: expected output not found at $OUTPUT"
  echo "Bazel bin contents:"
  find bazel-bin/litert/vendors/qualcomm/dispatch/ -name "*.so" 2>/dev/null || true
  exit 1
fi
cp "$OUTPUT" "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so"
chmod +w "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so"

echo ""
echo "=== Done ==="
echo "  libLiteRtDispatch_Qualcomm.so → $PREBUILT_DIR/"
ls -lh "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so"
echo ""
echo "Exported symbols (dispatch API):"
nm -D "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so" 2>/dev/null \
  | grep " T \|LiteRtGetDispatchApiVersion\|LiteRtInitialize" | head -10
