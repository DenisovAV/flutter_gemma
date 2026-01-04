#!/bin/bash
#
# LiteRT-LM Desktop Setup Script for Flutter Gemma (Linux)
#
# Downloads JRE, copies JAR, and extracts native libraries for Linux builds.
# Called by CMake during the build process.
#
# Usage: ./setup_desktop.sh <plugin_dir> <output_dir>

set -e

PLUGIN_DIR="$1"
OUTPUT_DIR="$2"

if [ -z "$PLUGIN_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <plugin_dir> <output_dir>"
    exit 1
fi

echo "=== LiteRT-LM Desktop Setup (Linux) ==="
echo "Plugin dir: $PLUGIN_DIR"
echo "Output dir: $OUTPUT_DIR"

# Configuration
JRE_VERSION="21.0.5+11"
JRE_VERSION_UNDERSCORE="${JRE_VERSION//+/_}"
CACHE_DIR="$HOME/.cache/flutter_gemma"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        JRE_ARCH="x64"
        NATIVE_ARCH="linux-x86_64"
        NATIVE_LIB="litertlm_jni.so"
        JRE_CHECKSUM="a59edb276b51d08a73c0908ab36c17c81cdfad12740e14404a2a70ae8a94a67e"
        echo "Detected x86_64 architecture"
        ;;
    aarch64)
        JRE_ARCH="aarch64"
        NATIVE_ARCH="linux-aarch64"
        NATIVE_LIB="litertlm_jni.so"
        JRE_CHECKSUM="a44c85cd2decfe67690e9e1dc77c058b3c0e55d79e5bb65d60ce5e42e5be814e"
        echo "Detected ARM64 architecture"
        ;;
    *)
        echo "========================================" >&2
        echo "ERROR: Unsupported architecture: $ARCH" >&2
        echo "========================================" >&2
        echo "LiteRT-LM only supports x86_64 and aarch64 Linux." >&2
        exit 1
        ;;
esac

# JRE settings (Adoptium Temurin)
JRE_ARCHIVE="OpenJDK21U-jre_${JRE_ARCH}_linux_hotspot_${JRE_VERSION_UNDERSCORE}.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JRE_VERSION}/${JRE_ARCHIVE}"

# JAR settings
JAR_NAME="litertlm-server.jar"
JAR_VERSION="0.11.16"
JAR_URL="https://github.com/DenisovAV/flutter_gemma/releases/download/v${JAR_VERSION}/${JAR_NAME}"
JAR_CHECKSUM="914b9d2526b5673eb810a6080bbc760e537322aaee8e19b9cd49609319cfbdc8"

# Plugin root (parent of linux/)
PLUGIN_ROOT=$(dirname "$PLUGIN_DIR")

# Create directories
mkdir -p "$OUTPUT_DIR"/{data,jre,litertlm}
mkdir -p "$CACHE_DIR"/{jre,jar}

# === Helper: Verify SHA256 checksum ===
verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual

    if command -v sha256sum &> /dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "WARNING: No sha256sum or shasum available, skipping checksum verification"
        return 0
    fi

    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Checksum mismatch!"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
    echo "Checksum verified"
    return 0
}

# === Download and install JRE ===
install_jre() {
    local JRE_DEST="$OUTPUT_DIR/jre"
    local JRE_MARKER="$JRE_DEST/.jre_installed"

    if [ -f "$JRE_MARKER" ]; then
        echo "JRE already installed"
        return
    fi

    echo "Setting up JRE..."
    local ARCHIVE="$CACHE_DIR/jre/$JRE_ARCHIVE"
    local EXTRACTED_DIR="$CACHE_DIR/jre/jdk-${JRE_VERSION}-jre"

    # Download if not cached
    if [ ! -f "$ARCHIVE" ]; then
        echo "Downloading JRE from $JRE_URL..."
        curl -L --progress-bar -o "$ARCHIVE" "$JRE_URL" || {
            echo "ERROR: Failed to download JRE"
            rm -f "$ARCHIVE"
            exit 1
        }

        # Verify checksum
        echo "Verifying JRE checksum..."
        if ! verify_checksum "$ARCHIVE" "$JRE_CHECKSUM"; then
            rm -f "$ARCHIVE"
            exit 1
        fi
    else
        echo "Using cached JRE archive"
    fi

    # Extract if needed
    local EXTRACTION_MARKER="$EXTRACTED_DIR/.extracted"
    if [ ! -f "$EXTRACTION_MARKER" ]; then
        echo "Extracting JRE..."
        rm -rf "$EXTRACTED_DIR"
        tar -xzf "$ARCHIVE" -C "$CACHE_DIR/jre"
        touch "$EXTRACTION_MARKER"
    fi

    # Copy to output
    echo "Copying JRE to output..."
    cp -r "$EXTRACTED_DIR"/* "$JRE_DEST/"

    # Verify critical file
    if [ ! -f "$JRE_DEST/lib/jvm.cfg" ]; then
        echo "ERROR: JRE copy failed - lib/jvm.cfg not found"
        exit 1
    fi

    touch "$JRE_MARKER"
    echo "JRE installed successfully"
}

# === Setup JAR (build or download) ===
setup_jar() {
    local JAR_DEST="$OUTPUT_DIR/data/$JAR_NAME"

    if [ -f "$JAR_DEST" ]; then
        echo "JAR already in output directory"
        return
    fi

    echo "Setting up JAR..."
    local JAR_SOURCE=""

    # 1. Check for locally built JAR first
    local LOCAL_JAR=$(find "$PLUGIN_ROOT/litertlm-server/build/libs" -name "*-all.jar" 2>/dev/null | sort -r | head -1)
    if [ -n "$LOCAL_JAR" ] && [ -f "$LOCAL_JAR" ]; then
        echo "Using locally built JAR: $LOCAL_JAR"
        JAR_SOURCE="$LOCAL_JAR"
    fi

    # 2. Try to build if JDK available (skip for now - just download)

    # 3. Download as fallback
    if [ -z "$JAR_SOURCE" ]; then
        local CACHED_JAR="$CACHE_DIR/jar/$JAR_NAME"

        if [ ! -f "$CACHED_JAR" ]; then
            echo "Downloading JAR from $JAR_URL..."
            curl -L --progress-bar -o "$CACHED_JAR" "$JAR_URL" || {
                echo "ERROR: Failed to download JAR"
                rm -f "$CACHED_JAR"
                exit 1
            }

            # Verify checksum
            echo "Verifying JAR checksum..."
            if ! verify_checksum "$CACHED_JAR" "$JAR_CHECKSUM"; then
                rm -f "$CACHED_JAR"
                exit 1
            fi
        else
            echo "Using cached JAR"
        fi

        JAR_SOURCE="$CACHED_JAR"
    fi

    # Copy to output
    cp "$JAR_SOURCE" "$JAR_DEST"
    echo "JAR installed successfully"
}

# === Extract native libraries from JAR ===
extract_natives() {
    local NATIVES_DIR="$OUTPUT_DIR/litertlm"
    local JAR_PATH="$OUTPUT_DIR/data/$JAR_NAME"

    if [ -f "$NATIVES_DIR/$NATIVE_LIB" ]; then
        echo "Native library already extracted: $NATIVE_LIB"
        return
    fi

    if [ ! -f "$JAR_PATH" ]; then
        echo "WARNING: JAR not found, skipping native extraction"
        return
    fi

    # Native path inside JAR
    # Format: com/google/ai/edge/litertlm/jni/linux-x86_64/litertlm_jni.so
    local NATIVE_ZIP_PATH="com/google/ai/edge/litertlm/jni/$NATIVE_ARCH/$NATIVE_LIB"
    echo "Extracting: $NATIVE_ZIP_PATH"

    # Extract using unzip (available on most Linux systems)
    if ! unzip -j -o "$JAR_PATH" "$NATIVE_ZIP_PATH" -d "$NATIVES_DIR" 2>/dev/null; then
        echo ""
        echo "========================================"
        echo "WARNING: Native library not found in JAR for $NATIVE_ARCH"
        echo "========================================"
        echo ""
        echo "Available native libraries in JAR:"
        unzip -l "$JAR_PATH" | grep -E "litertlm.*\.(so|dll|dylib)" || echo "  (none found)"
        echo ""
        echo "This architecture may not be supported by LiteRT-LM."
        echo "GPU inference will not work, but CPU inference may still work."
        echo ""
        return
    fi

    if [ -f "$NATIVES_DIR/$NATIVE_LIB" ]; then
        local SIZE=$(du -h "$NATIVES_DIR/$NATIVE_LIB" | cut -f1)
        echo "Extracted: $NATIVE_LIB ($SIZE)"
    fi
}

# === Main ===
echo ""
echo "=== Starting setup ==="

echo ""
echo "Step 1: Installing JRE..."
install_jre

echo ""
echo "Step 2: Setting up JAR..."
setup_jar

echo ""
echo "Step 3: Extracting native libraries..."
extract_natives

echo ""
echo "========================================"
echo "=== Setup complete ==="
echo "========================================"
echo "JRE:     $OUTPUT_DIR/jre"
echo "JAR:     $OUTPUT_DIR/data/$JAR_NAME"
echo "Natives: $OUTPUT_DIR/litertlm"
