#!/bin/bash
# Build libLiteRtLm.dylib for iOS device (arm64) and simulator (arm64).
#
# Prerequisites:
#   - Bazel (via bazelisk): brew install bazelisk
#   - Xcode with iOS SDK
#   - Git LFS: brew install git-lfs
#
# Usage:
#   ./build_ios.sh [ref]
#   ./build_ios.sh 032334d        # default for 0.15.0 (post-6571c42 main HEAD)
#   ./build_ios.sh v0.11.0        # WARNING: v0.11.0 prebuilt accelerators
#                                 # are ABI-incompatible with libLiteRtLm
#                                 # rebuilt from v0.11.0 source — crashes
#                                 # in libLiteRtMetalAccelerator on engine
#                                 # init/teardown. Use 032334d (post-6571c42
#                                 # which re-syncs accelerator binaries with
#                                 # WORKSPACE LITERT_REF).
#   ./build_ios.sh v0.10.2        # WARNING: predates Metal accelerator,
#                                 # produces libLiteRtLm.dylib that crashes
#                                 # iPhone GPU with EXC_BAD_ACCESS in
#                                 # litert_lm_engine_create.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LITERT_LM_DIR="${LITERT_LM_DIR:-/tmp/LiteRT-LM}"
VERSION="${1:-}"

echo "=== Building libLiteRtLm.dylib for iOS ==="

# 1. Clone or update LiteRT-LM
if [ -d "$LITERT_LM_DIR/.git" ]; then
  echo "Updating $LITERT_LM_DIR..."
  cd "$LITERT_LM_DIR"
  # --force so a tag that moved upstream (e.g. v0.11.0 itself was retagged
  # while we waited for accelerator fixes) doesn't abort the fetch.
  git fetch --tags --force origin
else
  echo "Cloning LiteRT-LM..."
  git clone https://github.com/google-ai-edge/LiteRT-LM "$LITERT_LM_DIR"
  cd "$LITERT_LM_DIR"
fi

# 2. Checkout version
# 032334d (main HEAD on 2026-05-08) is post-6571c42 "Update dependencies of
# litert_lm" which rebuilt all prebuilt accelerator dylibs (Metal, WebGPU,
# Gpu, OpenCL, samplers) AND re-synced WORKSPACE LITERT_REF to 5c5b9ce6.
# This is the first public LiteRT-LM commit where libLiteRtLm rebuilt from
# source has matching ABI with the prebuilt accelerators. v0.11.0 itself
# is broken — see the WARNING above and the upstream issue we filed.
DEFAULT_REF="ffed38adbc33509480b5340e5173638bc20a68ff"
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
        "@platforms//os:ios": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*", "-Wl,-x"],
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

verify_flutter_ios_strip() {
  local dylib="$1"
  local probe
  local output

  probe="$(mktemp)"
  cp "$dylib" "$probe"
  if ! output="$(xcrun strip -x -S "$probe" 2>&1)"; then
    rm -f "$probe"
    echo "ERROR: $dylib is not compatible with Flutter iOS Native Assets release stripping."
    echo "Flutter runs: xcrun strip -x -S <dylib>"
    printf '%s\n' "$output"
    return 1
  fi
  rm -f "$probe"
}

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

# 8b. Normalize iOS minos of all 4 companion dylibs to 13.0 — this matches
# the MinimumOSVersion that Flutter Native Assets hardcodes into the
# generated framework wrapper Info.plist (flutter/flutter#148501). Without
# this, App Store Connect rejects the archive with ITMS-90208 ("framework
# does not support the minimum OS Version specified in the Info.plist")
# whenever a dylib's binary minos differs from the wrapper plist's 13.0.
#
# The plugin still requires iOS 16+ via the podspec's `s.platform = :ios,
# '16.0'` — that's the real contract. The minos here is just metadata to
# satisfy validator equality between binary and wrapper plist; the actual
# minimum is enforced upstream by CocoaPods. See #245, #286.
echo ""
echo "=== Patch iOS companion dylibs minos → 13.0 ==="
for arch_dir_pair in "ios:$DEVICE_DIR" "iossim:$SIM_DIR"; do
  platform="${arch_dir_pair%%:*}"
  dir="${arch_dir_pair##*:}"
  for libname in libGemmaModelConstraintProvider libLiteRtLm libLiteRtMetalAccelerator libStreamProxy; do
    d="$dir/${libname}.dylib"
    if [ -f "$d" ]; then
      vtool -set-build-version "$platform" 13.0 18.5 -replace -output "$d.new" "$d"
      mv "$d.new" "$d"
      chmod +w "$d"
      echo "  $d: minos $(vtool -show-build "$d" | grep minos | awk '{print $2}'), sdk $(vtool -show-build "$d" | grep sdk | awk '{print $2}')"
    fi
  done
done

# 9. Verify
echo ""
echo "=== Verification ==="
echo "Device (ios_arm64):"
ls -lh "$DEVICE_DIR/"
nm -gU "$DEVICE_DIR/libLiteRtLm.dylib" | grep "litert_lm_engine_create" | head -1
for dylib in "$DEVICE_DIR"/*.dylib; do
  verify_flutter_ios_strip "$dylib"
done
echo ""
echo "Simulator (ios_sim_arm64):"
ls -lh "$SIM_DIR/"
nm -gU "$SIM_DIR/libLiteRtLm.dylib" | grep "litert_lm_engine_create" | head -1
for dylib in "$SIM_DIR"/*.dylib; do
  verify_flutter_ios_strip "$dylib"
done
echo ""
echo "=== Done ==="
