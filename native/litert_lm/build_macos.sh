#!/bin/bash
# Build libLiteRtLm.dylib for macOS arm64 from LiteRT-LM source.
#
# Prerequisites:
#   - Bazel (via bazelisk): brew install bazelisk
#   - Xcode command line tools
#   - Git LFS: brew install git-lfs
#
# Usage:
#   ./build_macos.sh [version]
#   ./build_macos.sh v0.10.1
#   ./build_macos.sh          # uses latest tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREBUILT_DIR="$SCRIPT_DIR/prebuilt/macos_arm64"
LITERT_LM_DIR="/tmp/LiteRT-LM"
VERSION="${1:-}"

echo "=== Building libLiteRtLm.dylib for macOS arm64 ==="

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

# 2. Checkout version
if [ -n "$VERSION" ]; then
  echo "Checking out $VERSION..."
  git checkout "$VERSION"
else
  LATEST_TAG=$(git tag -l "v*" | sort -V | tail -1)
  echo "Checking out latest tag: $LATEST_TAG..."
  git checkout "$LATEST_TAG"
fi

echo "Building from: $(git log --oneline -1)"

# 3. Ensure cc_binary(linkshared=True) target exists in c/BUILD
if ! grep -q "linkshared" c/BUILD; then
  echo "Adding shared library target to c/BUILD..."
  cat >> c/BUILD << 'BUILDEOF'

cc_binary(
    name = "libLiteRtLm.dylib",
    linkshared = True,
    visibility = ["//visibility:public"],
    deps = [":engine"],
)
BUILDEOF
fi

# 4. Pull LFS files (prebuilt companion libs)
echo "Pulling LFS files..."
git lfs pull --include="prebuilt/macos_arm64/*"

# 5. Build
echo "Building with Bazel..."
bazelisk build --config=macos_arm64 '//c:libLiteRtLm.dylib'

# 6. Copy to prebuilt
BUILT_LIB="bazel-bin/c/libLiteRtLm.dylib"
if [ ! -f "$BUILT_LIB" ]; then
  echo "ERROR: Build output not found: $BUILT_LIB"
  exit 1
fi

mkdir -p "$PREBUILT_DIR"

# Fix install_name and add rpath for framework bundle layout
cp "$BUILT_LIB" "$PREBUILT_DIR/libLiteRtLm.dylib"
chmod +w "$PREBUILT_DIR/libLiteRtLm.dylib"
install_name_tool -id @rpath/libLiteRtLm.dylib "$PREBUILT_DIR/libLiteRtLm.dylib"
install_name_tool -add_rpath '@loader_path/../../..' "$PREBUILT_DIR/libLiteRtLm.dylib" 2>/dev/null || true

# Copy companion libs from prebuilt
for lib in libGemmaModelConstraintProvider.dylib libLiteRtMetalAccelerator.dylib; do
  if [ -f "prebuilt/macos_arm64/$lib" ]; then
    cp "prebuilt/macos_arm64/$lib" "$PREBUILT_DIR/$lib"
    echo "Copied $lib"
  fi
done

# 7. Build stream proxy
echo "Building stream proxy..."
clang -shared -o "$PREBUILT_DIR/libStreamProxy.dylib" \
  -arch arm64 \
  -install_name @rpath/libStreamProxy.dylib \
  -Wl,-headerpad_max_install_names \
  "$SCRIPT_DIR/stream_proxy.c"

# 8. Verify
echo ""
echo "=== Verification ==="
echo "Symbols:"
nm -gU "$PREBUILT_DIR/libLiteRtLm.dylib" | grep "litert_lm_engine_create" | head -2
echo ""
echo "Files:"
ls -lh "$PREBUILT_DIR/"
echo ""
echo "=== Done ==="
echo "Version: $(git describe --tags --always)"
