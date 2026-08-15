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

# 2. Build dispatch lib.
#
# The NDK path goes in via --repo_env, NOT --action_env. At this pin LiteRT
# resolves the toolchain through rules_android_ndk and gates it on a repository
# rule: check_android_ndk_env() reads ctx.getenv("ANDROID_NDK_HOME") and, when
# it comes back empty, registers @android_ndk_env//:all — a repo with an EMPTY
# BUILD file. Zero toolchains, cc resolution finds nothing, Bazel falls back to
# the legacy crosstool, and you get `clang: error: unknown argument:
# '-gcc-toolchain'` — which reads as "NDK too new" and is not.
#
# --action_env populates action environments, which repo rules never read. The
# old .litert_configure.bazelrc written here (ANDROID_NDK_API_LEVEL and
# friends) was the pre-rules_android_ndk mechanism and is dead weight now:
# api_level is declared in LiteRT's own WORKSPACE call.
echo ""
echo "=== Running Bazel build ==="
bazelisk build \
  --repo_env=ANDROID_NDK_HOME="$ANDROID_NDK_HOME" \
  --repo_env=ANDROID_HOME="$ANDROID_HOME" \
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

# 4. Refresh the QNN runtime from the SAME QAIRT the dispatch was built against.
#
# These are not compiled from source — they come out of the QAIRT SDK — which
# makes "keep the old ones" look safe. It is not: the dispatch negotiates an
# API version with them. Ours drifted to
#   qnn_manager.cc:349 Qnn System library version 1.8.0 is mismatched.
#                      The minimum supported version is 1.11.0.
#   dispatch_api.cc:139 Failed to set up QNN manager
#   dispatch_delegate.cc:131 No usable Dispatch runtime found
# and engine_create then fails on backend=npu in ~60ms with nothing but an
# opaque null, which the Dart layer reports as "model may be invalid".
#
# Do NOT try to catch this by version string: QNN has two independent
# numberings, and libQnnSystem.so — the file that actually broke — carries no
# version string at all. Compare sizes against the SDK instead.
QAIRT_DIR="$(bazelisk info output_base 2>/dev/null)/external/qairt"
if [ ! -d "$QAIRT_DIR/lib/aarch64-android" ]; then
  echo "ERROR: QAIRT SDK not found at $QAIRT_DIR" >&2
  echo "       The QNN runtime was NOT refreshed. Shipping a runtime older than" >&2
  echo "       the dispatch fails only on real hardware, at engine_create." >&2
  exit 1
fi
echo ""
echo "=== Refreshing QNN runtime from $QAIRT_DIR ==="
for f in libQnnSystem.so libQnnHtp.so \
         libQnnHtpV73Stub.so libQnnHtpV75Stub.so \
         libQnnHtpV79Stub.so libQnnHtpV81Stub.so; do
  src="$QAIRT_DIR/lib/aarch64-android/$f"
  [ -f "$src" ] || { echo "ERROR: missing in SDK: $src" >&2; exit 1; }
  cp -f "$src" "$PREBUILT_DIR/$f"
  chmod +w "$PREBUILT_DIR/$f"
  printf "  %-26s %s bytes\n" "$f" "$(wc -c < "$PREBUILT_DIR/$f" | tr -d ' ')"
done
# Skel libs live per-Hexagon-version, outside lib/aarch64-android. V79 is the
# HTP of SM8750 (Snapdragon 8 Elite) and is absent from /vendor/dsp/cdsp/ even
# on Qualcomm reference firmware, so bundling it is required, not a workaround.
for v in 73 75 79 81; do
  src="$QAIRT_DIR/lib/hexagon-v$v/unsigned/libQnnHtpV${v}Skel.so"
  [ -f "$src" ] || { echo "ERROR: missing in SDK: $src" >&2; exit 1; }
  cp -f "$src" "$PREBUILT_DIR/libQnnHtpV${v}Skel.so"
  chmod +w "$PREBUILT_DIR/libQnnHtpV${v}Skel.so"
  printf "  %-26s %s bytes\n" "libQnnHtpV${v}Skel.so" "$(wc -c < "$PREBUILT_DIR/libQnnHtpV${v}Skel.so" | tr -d ' ')"
done

echo ""
echo "=== Done ==="
echo "  libLiteRtDispatch_Qualcomm.so + 10 QNN runtime libs → $PREBUILT_DIR/"
ls -lh "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so"
echo ""
echo "Exported symbols (dispatch API):"
nm -D "$PREBUILT_DIR/libLiteRtDispatch_Qualcomm.so" 2>/dev/null \
  | grep " T \|LiteRtGetDispatchApiVersion\|LiteRtInitialize" | head -10
