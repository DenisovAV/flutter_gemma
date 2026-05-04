#!/bin/bash
# Build libLiteRtLm.dylib for iOS device (arm64) and simulator (arm64).
#
# Prerequisites:
#   - Bazel (via bazelisk): brew install bazelisk
#   - Xcode with iOS SDK
#   - Git LFS: brew install git-lfs
#
# Usage:
#   ./build_ios.sh [version]
#   ./build_ios.sh                # default: commit 5e0d86b (required for GPU)
#   ./build_ios.sh 5e0d86b        # explicit
#   ./build_ios.sh v0.10.2        # WARNING: predates Metal accelerator,
#                                 # produces libLiteRtLm.dylib that crashes
#                                 # iPhone GPU with EXC_BAD_ACCESS in
#                                 # litert_lm_engine_create.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LITERT_LM_DIR="/tmp/LiteRT-LM"
VERSION="${1:-}"

echo "=== Building libLiteRtLm.dylib for iOS ==="

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
# Default to commit 5e0d86b (post-v0.10.2) because it's the first commit that
# adds libLiteRtMetalAccelerator.dylib for iOS — required for GPU. Building
# against an earlier ref (e.g. v0.10.2) produces a libLiteRtLm.dylib whose
# Metal accelerator ABI doesn't match the prebuilt framework, causing
# EXC_BAD_ACCESS in litert_lm_engine_create at runtime on iPhone GPU.
DEFAULT_REF="5e0d86b"
TARGET_REF="${VERSION:-$DEFAULT_REF}"
echo "Checking out $TARGET_REF..."
git checkout -f "$TARGET_REF"
echo "Building from: $(git log --oneline -1)"

# 3. Ensure shared library target exists
if ! grep -q "linkshared" c/BUILD; then
  echo "Adding shared library target to c/BUILD..."
  cat >> c/BUILD << 'BUILDEOF'

cc_binary(
    name = "libLiteRtLm.dylib",
    linkshared = True,
    linkopts = select({
        "@platforms//os:macos": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:ios": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:linux": ["-Wl,--export-dynamic-symbol=LiteRt*", "-Wl,--export-dynamic-symbol=litert_lm_*"],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
    deps = [":engine"],
)
BUILDEOF
fi

# 3b. Apply C API patch (adds set_max_num_images, set_litert_dispatch_lib_dir, etc).
# git checkout above resets the source tree, so we re-apply on every build.
bash "$SCRIPT_DIR/patch_c_api.sh" "$LITERT_LM_DIR"

# 4. Pull LFS files
echo "Pulling LFS files..."
git lfs pull --include="prebuilt/ios_arm64/*,prebuilt/ios_sim_arm64/*"

# 5. Build for iOS device (arm64)
echo ""
echo "=== Building for iOS device (arm64) ==="
bazelisk build -c opt --strip=always --config=ios_arm64 '//c:libLiteRtLm.dylib'
DEVICE_DIR="$SCRIPT_DIR/prebuilt/ios_arm64"
mkdir -p "$DEVICE_DIR"
cp bazel-bin/c/libLiteRtLm.dylib "$DEVICE_DIR/"
chmod +w "$DEVICE_DIR/libLiteRtLm.dylib"
install_name_tool -id @rpath/libLiteRtLm.dylib "$DEVICE_DIR/libLiteRtLm.dylib"
install_name_tool -add_rpath '@loader_path/../../..' "$DEVICE_DIR/libLiteRtLm.dylib" 2>/dev/null || true

# 6. Build for iOS simulator (arm64)
echo ""
echo "=== Building for iOS simulator (arm64) ==="
bazelisk build --config=ios_sim_arm64 '//c:libLiteRtLm.dylib'
SIM_DIR="$SCRIPT_DIR/prebuilt/ios_sim_arm64"
mkdir -p "$SIM_DIR"
cp bazel-bin/c/libLiteRtLm.dylib "$SIM_DIR/"
chmod +w "$SIM_DIR/libLiteRtLm.dylib"
install_name_tool -id @rpath/libLiteRtLm.dylib "$SIM_DIR/libLiteRtLm.dylib"
install_name_tool -add_rpath '@loader_path/../../..' "$SIM_DIR/libLiteRtLm.dylib" 2>/dev/null || true

# 7. Build StreamProxy for both targets
echo ""
echo "=== Building StreamProxy ==="
clang -shared -o "$DEVICE_DIR/libStreamProxy.dylib" \
  -arch arm64 -target arm64-apple-ios16.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -install_name @rpath/libStreamProxy.dylib \
  -Wl,-headerpad_max_install_names \
  "$SCRIPT_DIR/stream_proxy.c"
echo "StreamProxy (device): OK"

clang -shared -o "$SIM_DIR/libStreamProxy.dylib" \
  -arch arm64 -target arm64-apple-ios16.0-simulator \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -install_name @rpath/libStreamProxy.dylib \
  -Wl,-headerpad_max_install_names \
  "$SCRIPT_DIR/stream_proxy.c"
echo "StreamProxy (simulator): OK"

# 8. Copy companion libs
echo ""
echo "=== Copying companion libs ==="
# libLiteRtMetalAccelerator.dylib was added upstream in commit 5e0d86b ("Update
# dependencies of litert_lm") — must be on a tag/commit that includes it. The
# v0.10.2 tag predates that commit. libLiteRt.dylib and libLiteRtTopKMetalSampler.dylib
# in 5e0d86b are mistakenly x86_64 macOS binaries (upstream issue #2072), so we
# only pick up the Metal accelerator which is actually arm64 iOS / arm64 iOSSim.
for lib in libGemmaModelConstraintProvider.dylib libLiteRtMetalAccelerator.dylib; do
  [ -f "prebuilt/ios_arm64/$lib" ] && cp "prebuilt/ios_arm64/$lib" "$DEVICE_DIR/$lib" && echo "  $lib → device"
  [ -f "prebuilt/ios_sim_arm64/$lib" ] && cp "prebuilt/ios_sim_arm64/$lib" "$SIM_DIR/$lib" && echo "  $lib → simulator"
done

# 8b. Re-apply vtool minos patch on libGemmaModelConstraintProvider.dylib —
# upstream ships it with minos 26.2 on iOS (only one of the iOS companion
# dylibs with this issue), causing App Store ITMS-90208 rejection for any
# app with Info.plist min iOS < 26.2. See google-ai-edge/LiteRT-LM#2158
# and our downstream issue #245. Lower to 16.0 which matches our podspec.
echo ""
echo "=== Patch libGemmaModelConstraintProvider.dylib minos 26.2 → 16.0 ==="
for arch_dir_pair in "ios:$DEVICE_DIR" "iossim:$SIM_DIR"; do
  platform="${arch_dir_pair%%:*}"
  dir="${arch_dir_pair##*:}"
  d="$dir/libGemmaModelConstraintProvider.dylib"
  if [ -f "$d" ]; then
    vtool -set-build-version "$platform" 16.0 26.2 -replace -output "$d.new" "$d"
    mv "$d.new" "$d"
    chmod +w "$d"
    echo "  $d: minos $(vtool -show-build "$d" | grep minos | awk '{print $2}')"
  fi
done

# 9. Verify
echo ""
echo "=== Verification ==="
echo "Device (ios_arm64):"
ls -lh "$DEVICE_DIR/"
nm -gU "$DEVICE_DIR/libLiteRtLm.dylib" | grep "litert_lm_engine_create" | head -1
echo ""
echo "Simulator (ios_sim_arm64):"
ls -lh "$SIM_DIR/"
nm -gU "$SIM_DIR/libLiteRtLm.dylib" | grep "litert_lm_engine_create" | head -1
echo ""
echo "=== Done ==="
