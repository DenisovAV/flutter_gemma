#!/bin/bash
# Build libLiteRtLm.so for Android arm64 from LiteRT-LM source.
#
# Cross-compile from macOS host using Android NDK + Bazel.
#
# Prerequisites:
#   - Bazel (via bazelisk): brew install bazelisk
#   - Android NDK at ~/Library/Android/sdk/ndk/<version>/
#     (typically installed by Android Studio)
#   - Git LFS: brew install git-lfs
#
# Usage:
#   ./build_android.sh [version]
#   ./build_android.sh 5e0d86b
#   ./build_android.sh          # uses latest tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREBUILT_DIR="$SCRIPT_DIR/prebuilt/android_arm64"
LITERT_LM_DIR="/tmp/LiteRT-LM"
VERSION="${1:-}"

# Resolve Android NDK — prefer ANDROID_NDK_HOME env, else newest under
# Android Studio default location.
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

# bazel rules_android needs ANDROID_HOME too — synthesize from NDK parent.
if [ -z "${ANDROID_HOME:-}" ]; then
  export ANDROID_HOME="$(dirname "$(dirname "$ANDROID_NDK_HOME")")"
  echo "Auto-detected ANDROID_HOME=$ANDROID_HOME"
fi

echo "=== Building libLiteRtLm.so for Android arm64 ==="
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo "ANDROID_HOME: $ANDROID_HOME"

# 1. Clone or update LiteRT-LM
if [ -d "$LITERT_LM_DIR" ]; then
  echo "Updating $LITERT_LM_DIR..."
  cd "$LITERT_LM_DIR"
  git fetch --tags
else
  echo "Cloning LiteRT-LM..."
  git clone https://github.com/google-ai-edge/LiteRT-LM "$LITERT_LM_DIR"
  cd "$LITERT_LM_DIR"
fi

# 2. Checkout version (-f to discard any patch leftovers)
if [ -n "$VERSION" ]; then
  echo "Checking out $VERSION..."
  git checkout -f "$VERSION"
else
  LATEST_TAG=$(git tag -l "v*" | sort -V | tail -1)
  echo "Checking out latest tag: $LATEST_TAG..."
  git checkout -f "$LATEST_TAG"
fi
echo "Building from: $(git log --oneline -1)"

# 3. Ensure cc_binary(linkshared=True) target exists in c/BUILD
if ! grep -q "linkshared" c/BUILD; then
  cat >> c/BUILD << 'BUILDEOF'

cc_binary(
    name = "libLiteRtLm.dylib",
    linkshared = True,
    linkopts = select({
        "@platforms//os:android": ["-Wl,-soname,libLiteRtLm.so"],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
    deps = [":engine"],
)
BUILDEOF
fi

# 3b. Apply C API patch.
bash "$SCRIPT_DIR/patch_c_api.sh" "$LITERT_LM_DIR"

# 4. Pull LFS files
echo "Pulling LFS files..."
git lfs pull --include="prebuilt/android_arm64/*"

# 5. Build for Android arm64
echo ""
echo "=== Building for Android arm64 ==="
# Note: NOT using --define=litert_link_capi_so=true. On Linux/Windows that
# flag tells libLiteRtLm to dynamically resolve LiteRt* symbols against a
# separate libLiteRt.so we ship alongside, and we preload it via RTLD_GLOBAL
# from Dart. On Android, upstream's prebuilt accelerator libs are already
# linked against a fully self-contained libLiteRtLm.so (LiteRt symbols
# linked statically into libLiteRtLm.so), so we build the same way.
#
# 16KB page size support (Android 15+ on Pixel 8 and beyond, mandatory for
# Google Play uploads since Nov 2025 — see #253). max-page-size=16384 makes
# the linker pad PT_LOAD segments to 16KB boundaries; the binary is still
# loadable on 4KB-page kernels, just ~12KB larger per segment.
bazelisk build \
  -c opt \
  --strip=always \
  --config=android_arm64 \
  --linkopt=-Wl,-z,max-page-size=16384 \
  '//c:libLiteRtLm.dylib'

# 6. Copy + rename .dylib → .so (bazel target name is hardcoded to .dylib).
mkdir -p "$PREBUILT_DIR"
cp bazel-bin/c/libLiteRtLm.dylib "$PREBUILT_DIR/libLiteRtLm.so"
chmod +w "$PREBUILT_DIR/libLiteRtLm.so"
echo "  libLiteRtLm.so → $PREBUILT_DIR/"

# 7. Build StreamProxy for Android (cross-compile via NDK toolchain).
NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
if [ ! -d "$NDK_TOOLCHAIN" ]; then
  # Apple silicon hosts: NDK r26+ has darwin-x86_64 with x86_64 binaries
  # that run via Rosetta. r28+ may have native arm64 — try that first.
  NDK_TOOLCHAIN_ARM64="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64"
  if [ -d "$NDK_TOOLCHAIN_ARM64" ]; then
    NDK_TOOLCHAIN="$NDK_TOOLCHAIN_ARM64"
  fi
fi
NDK_CLANG="$NDK_TOOLCHAIN/bin/aarch64-linux-android24-clang"
if [ ! -x "$NDK_CLANG" ]; then
  echo "ERROR: NDK clang not found at $NDK_CLANG"
  echo "Available toolchain bins:"
  ls "$NDK_TOOLCHAIN/bin/" 2>/dev/null | head -20
  exit 2
fi

echo ""
echo "=== Building StreamProxy with $NDK_CLANG ==="
# 16KB page-size flag for Google Play parity with libLiteRtLm.so build above.
# NDK r25+ defaults to this anyway, but make it explicit so older NDKs work.
"$NDK_CLANG" -shared -fPIC \
  -Wl,-z,max-page-size=16384 \
  -o "$PREBUILT_DIR/libStreamProxy.so" \
  "$SCRIPT_DIR/stream_proxy.c"
echo "  libStreamProxy.so → $PREBUILT_DIR/"

# 8. Copy companion libs from upstream prebuilt (we don't rebuild these
#    — they're Google's GPU accelerator + sampler binaries).
echo ""
echo "=== Copying companion libs from upstream prebuilt ==="
for lib in libGemmaModelConstraintProvider.so \
           libLiteRtGpuAccelerator.so \
           libLiteRtOpenClAccelerator.so \
           libLiteRtTopKOpenClSampler.so \
           libLiteRtTopKWebGpuSampler.so \
           libLiteRtWebGpuAccelerator.so; do
  if [ -f "prebuilt/android_arm64/$lib" ]; then
    cp "prebuilt/android_arm64/$lib" "$PREBUILT_DIR/$lib"
    echo "  $lib"
  else
    echo "  WARN: prebuilt/android_arm64/$lib not found in upstream"
  fi
done

# 9. Verify
echo ""
echo "=== Verification ==="
ls -lh "$PREBUILT_DIR/" | head -20
echo ""
echo "Symbols (libLiteRtLm.so):"
nm -D "$PREBUILT_DIR/libLiteRtLm.so" 2>/dev/null | grep -i "litert_lm_engine_create\|SetPendingSamplerParams" | head -5

echo ""
echo "=== Done ==="
echo "Version: $(cd $LITERT_LM_DIR && git log --oneline -1)"
