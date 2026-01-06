#!/bin/bash
# LiteRT-LM native libraries setup
#
# NOTE: As of LiteRT-LM JVM 0.9.0+, native libraries are BUNDLED inside the JAR.
# This script is NO LONGER NEEDED for basic operation.
#
# The fat JAR (litertlm-server-0.1.0-all.jar) includes:
#   - darwin-aarch64/liblitertlm_jni.so (macOS ARM64)
#   - linux-aarch64/liblitertlm_jni.so (Linux ARM64)
#   - linux-x86_64/liblitertlm_jni.so (Linux x64)
#   - windows-x86_64/litertlm_jni.dll (Windows x64)
#
# These are automatically extracted and loaded at runtime.
#
# This script is kept for reference or future GPU accelerator libraries.

echo "ℹ️  Native libraries are bundled in the JAR (LiteRT-LM JVM 0.9.0+)"
echo "   No additional setup required!"
echo ""
echo "   To verify, run:"
echo "   unzip -l build/libs/litertlm-server-0.1.0-all.jar | grep litertlm_jni"
exit 0

# Legacy code below (kept for reference)
# ---

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NATIVES_DIR="$PROJECT_DIR/natives"

# LiteRT-LM release info
LITERTLM_VERSION="0.8.1"
LITERTLM_RELEASE_URL="https://github.com/google-ai-edge/LiteRT-LM/releases/download/v${LITERTLM_VERSION}"

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

PLATFORM="${1:-$(detect_platform)}"

echo "🔧 Setting up LiteRT-LM native libraries for $PLATFORM..."

# Create natives directory
mkdir -p "$NATIVES_DIR/$PLATFORM"

cd "$NATIVES_DIR/$PLATFORM"

case "$PLATFORM" in
    macos)
        echo "📥 Downloading macOS native libraries..."
        # Metal accelerator for macOS
        NATIVE_FILE="libLiteRtMetalAccelerator.dylib"
        DOWNLOAD_URL="${LITERTLM_RELEASE_URL}/litertlm-natives-macos-arm64.tar.gz"

        if [ -f "$NATIVE_FILE" ]; then
            echo "ℹ️  $NATIVE_FILE already exists, skipping download"
        else
            echo "   Downloading from: $DOWNLOAD_URL"
            if curl -L -o natives.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
                tar -xzf natives.tar.gz
                rm natives.tar.gz
                echo "✅ Downloaded macOS natives"
            else
                echo "⚠️  Download failed. You may need to download manually from:"
                echo "   https://github.com/google-ai-edge/LiteRT-LM/releases"
                echo ""
                echo "   Expected files for macOS:"
                echo "   - libLiteRtMetalAccelerator.dylib"
            fi
        fi
        ;;

    linux)
        echo "📥 Downloading Linux native libraries..."
        NATIVE_FILE="libLiteRtGpuAccelerator.so"
        DOWNLOAD_URL="${LITERTLM_RELEASE_URL}/litertlm-natives-linux-x64.tar.gz"

        if [ -f "$NATIVE_FILE" ]; then
            echo "ℹ️  $NATIVE_FILE already exists, skipping download"
        else
            echo "   Downloading from: $DOWNLOAD_URL"
            if curl -L -o natives.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
                tar -xzf natives.tar.gz
                rm natives.tar.gz
                echo "✅ Downloaded Linux natives"
            else
                echo "⚠️  Download failed. You may need to download manually."
            fi
        fi
        ;;

    windows)
        echo "📥 Downloading Windows native libraries..."
        NATIVE_FILE="LiteRtGpuAccelerator.dll"
        DOWNLOAD_URL="${LITERTLM_RELEASE_URL}/litertlm-natives-windows-x64.zip"

        if [ -f "$NATIVE_FILE" ]; then
            echo "ℹ️  $NATIVE_FILE already exists, skipping download"
        else
            echo "   Downloading from: $DOWNLOAD_URL"
            if curl -L -o natives.zip "$DOWNLOAD_URL" 2>/dev/null; then
                unzip -o natives.zip
                rm natives.zip
                echo "✅ Downloaded Windows natives"
            else
                echo "⚠️  Download failed. You may need to download manually."
            fi
        fi
        ;;

    *)
        echo "❌ Unknown platform: $PLATFORM"
        echo "   Supported platforms: macos, linux, windows"
        exit 1
        ;;
esac

echo ""
echo "📁 Native libraries location: $NATIVES_DIR/$PLATFORM"
ls -la "$NATIVES_DIR/$PLATFORM" 2>/dev/null || echo "   (empty)"
