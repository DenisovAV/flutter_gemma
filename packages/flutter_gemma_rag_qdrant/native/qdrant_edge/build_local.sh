#!/usr/bin/env bash
# Build qdrant_edge_ffi dylib for the 4 platforms we build LOCALLY on macOS
# (the other 3 — linux x86_64/arm64, windows x86_64 — are built on CI by
# .github/workflows/build-qdrant-edge-native.yml).
#
# Inputs : QDRANT_EDGE_VERSION env (default: "0.6.1-flutter1")
# Outputs: dist/qdrant-edge-{macos,ios,ios_sim,android}_arm64.tar.gz
#          dist/checksums_qdrant_edge_local.txt
#
# Usage:
#   ./native/qdrant_edge/build_local.sh                # build all 4
#   ./native/qdrant_edge/build_local.sh macos          # one target
#
# Targets (lowercase keys, match hook/build.dart suffixes):
#   macos     → aarch64-apple-darwin       → libqdrant_edge_ffi.dylib
#   ios       → aarch64-apple-ios          → libqdrant_edge_ffi.dylib (device)
#   ios_sim   → aarch64-apple-ios-sim      → libqdrant_edge_ffi.dylib (simulator)
#   android   → aarch64-linux-android (cargo-ndk) → libqdrant_edge_ffi.so

set -euo pipefail

QDRANT_EDGE_VERSION="${QDRANT_EDGE_VERSION:-0.7.2}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-24}"  # minSdk 24 matches flutter_gemma

# iOS deployment target. Must match flutter_gemma's Podfile (platform :ios, '16.0').
# Without this, cc-rs builds C deps (zstd_sys etc.) against the current Xcode
# SDK but Rust links with the old default minos=10.0, producing undefined
# symbols like __chkstk_darwin which only exist on iOS 12+.
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

# qdrant-edge 0.7+ uses features stabilized in Rust 1.95.0 (cfg_select,
# if_let_guard, ptr_as_ref_unchecked). On macOS, Homebrew rustc may lag behind
# rustup's stable — prefer rustup's compiler when available.
if command -v rustup &>/dev/null; then
  _rustup_rustc="$(rustup which rustc 2>/dev/null || true)"
  if [[ -n "$_rustup_rustc" ]]; then
    export RUSTC="$_rustup_rustc"
    echo "Using rustup rustc: $("$RUSTC" --version)"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_DIR="$SCRIPT_DIR/qdrant_edge_ffi"
DIST_DIR="$SCRIPT_DIR/dist"

mkdir -p "$DIST_DIR"

# Persisted across runs — important for cold rebuilds (~10 min) → warm (~1 min).
cd "$SHIM_DIR"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ANDROID_NDK_HOME is unset. Set it to a valid NDK r26+ path." >&2
    exit 1
fi

build_macos_arm64() {
    echo "==> macOS arm64 (aarch64-apple-darwin)"
    cargo build --release --target aarch64-apple-darwin
    local src="target/aarch64-apple-darwin/release/libqdrant_edge_ffi.dylib"
    local out="$DIST_DIR/qdrant-edge-macos_arm64"
    rm -rf "$out" && mkdir -p "$out"
    cp "$src" "$out/libqdrant_edge_ffi.dylib"
    install_name_tool -id "@rpath/libqdrant_edge_ffi.dylib" "$out/libqdrant_edge_ffi.dylib"
    tar -czf "$DIST_DIR/qdrant-edge-macos_arm64.tar.gz" -C "$out" .
    echo "    → $DIST_DIR/qdrant-edge-macos_arm64.tar.gz"
}

build_ios_device() {
    echo "==> iOS arm64 device (aarch64-apple-ios)"
    cargo build --release --target aarch64-apple-ios
    local src="target/aarch64-apple-ios/release/libqdrant_edge_ffi.dylib"
    local out="$DIST_DIR/qdrant-edge-ios_arm64"
    rm -rf "$out" && mkdir -p "$out"
    cp "$src" "$out/libqdrant_edge_ffi.dylib"
    install_name_tool -id "@rpath/libqdrant_edge_ffi.dylib" "$out/libqdrant_edge_ffi.dylib"
    # Normalize iOS minos -> 13.0 to match the MinimumOSVersion Flutter Native
    # Assets hardcodes into the framework wrapper Info.plist. Without this, App
    # Store Connect rejects the archive with ITMS-90208 because the binary minos
    # (16.0, from IPHONEOS_DEPLOYMENT_TARGET above) differs from the wrapper's
    # 13.0. The real iOS 16+ floor is enforced by the podspec, not this metadata.
    # Same patch as native/litert_lm/build_ios.sh. See #245, #286.
    vtool -set-build-version ios 13.0 18.5 -replace \
        -output "$out/libqdrant_edge_ffi.dylib" "$out/libqdrant_edge_ffi.dylib"
    echo "    minos -> $(vtool -show-build "$out/libqdrant_edge_ffi.dylib" | awk '/minos/{print $2}')"
    tar -czf "$DIST_DIR/qdrant-edge-ios_arm64.tar.gz" -C "$out" .
    echo "    → $DIST_DIR/qdrant-edge-ios_arm64.tar.gz"
}

build_ios_sim() {
    echo "==> iOS arm64 simulator (aarch64-apple-ios-sim)"
    cargo build --release --target aarch64-apple-ios-sim
    local src="target/aarch64-apple-ios-sim/release/libqdrant_edge_ffi.dylib"
    local out="$DIST_DIR/qdrant-edge-ios_sim_arm64"
    rm -rf "$out" && mkdir -p "$out"
    cp "$src" "$out/libqdrant_edge_ffi.dylib"
    install_name_tool -id "@rpath/libqdrant_edge_ffi.dylib" "$out/libqdrant_edge_ffi.dylib"
    # See build_ios_device — same ITMS-90208 minos normalization, simulator
    # platform token (iossim, not ios).
    vtool -set-build-version iossim 13.0 18.5 -replace \
        -output "$out/libqdrant_edge_ffi.dylib" "$out/libqdrant_edge_ffi.dylib"
    echo "    minos -> $(vtool -show-build "$out/libqdrant_edge_ffi.dylib" | awk '/minos/{print $2}')"
    tar -czf "$DIST_DIR/qdrant-edge-ios_sim_arm64.tar.gz" -C "$out" .
    echo "    → $DIST_DIR/qdrant-edge-ios_sim_arm64.tar.gz"
}

build_android_arm64() {
    echo "==> Android arm64 (aarch64-linux-android, NDK $ANDROID_NDK_HOME, API $ANDROID_API_LEVEL)"
    # 16 KB ELF LOAD-segment alignment — required for Android 15 (16 KB pages)
    # and Google Play target SDK 35+ uploads (#319). Matches the LiteRT libs'
    # max-page-size=16384 (#253). Passed as a Rust linker arg so cargo-ndk
    # threads it through to the NDK linker.
    RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384" \
      cargo ndk -t arm64-v8a --platform "$ANDROID_API_LEVEL" -- build --release
    local src="target/aarch64-linux-android/release/libqdrant_edge_ffi.so"
    local out="$DIST_DIR/qdrant-edge-android_arm64"
    rm -rf "$out" && mkdir -p "$out"
    cp "$src" "$out/libqdrant_edge_ffi.so"
    tar -czf "$DIST_DIR/qdrant-edge-android_arm64.tar.gz" -C "$out" .
    echo "    → $DIST_DIR/qdrant-edge-android_arm64.tar.gz"
}

case "${1:-all}" in
    all)
        build_macos_arm64
        build_ios_device
        build_ios_sim
        build_android_arm64
        ;;
    macos) build_macos_arm64 ;;
    ios) build_ios_device ;;
    ios_sim) build_ios_sim ;;
    android) build_android_arm64 ;;
    *)
        echo "Unknown target: $1" >&2
        echo "Valid: all | macos | ios | ios_sim | android" >&2
        exit 1
        ;;
esac

echo
echo "==> checksums"
(cd "$DIST_DIR" && shasum -a 256 qdrant-edge-*.tar.gz | tee checksums_qdrant_edge_local.txt)

echo
echo "Done. Artifacts in: $DIST_DIR"
