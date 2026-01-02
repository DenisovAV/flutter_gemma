#!/bin/bash
# LiteRT-LM Desktop Setup Script
# Downloads JRE and copies JAR to app bundle
#
# Usage: setup_desktop.sh <PODS_TARGET_SRCROOT> <FRAMEWORKS_PATH>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PODS_ROOT="${1:-$SCRIPT_DIR/..}"
FRAMEWORKS_PATH="${2:-}"

# Paths
PLUGIN_ROOT="$(cd "$PODS_ROOT/.." && pwd)"
JRE_VERSION="21.0.5+11"
JRE_ARCHIVE="OpenJDK21U-jre_aarch64_mac_hotspot_${JRE_VERSION/+/_}.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JRE_VERSION}/${JRE_ARCHIVE}"
JRE_CACHE_DIR="$HOME/.cache/flutter_gemma/jre"
JAR_NAME="litertlm-server.jar"

echo "=== LiteRT-LM Desktop Setup ==="
echo "Plugin root: $PLUGIN_ROOT"
echo "Frameworks path: $FRAMEWORKS_PATH"

# Skip if not macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping: not macOS"
    exit 0
fi

# Function to download JRE
download_jre() {
    local jre_dir="$1"

    if [[ -f "$jre_dir/bin/java" ]]; then
        echo "JRE already present at $jre_dir"
        return 0
    fi

    echo "Downloading JRE from $JRE_URL..."
    mkdir -p "$JRE_CACHE_DIR"

    local archive="$JRE_CACHE_DIR/$JRE_ARCHIVE"
    if [[ ! -f "$archive" ]]; then
        curl -L -o "$archive" "$JRE_URL"
    fi

    echo "Extracting JRE..."
    mkdir -p "$jre_dir"
    tar -xzf "$archive" -C "$JRE_CACHE_DIR"

    # Copy contents (strip top-level folder)
    local extracted_dir="$JRE_CACHE_DIR/jdk-${JRE_VERSION}-jre/Contents/Home"
    if [[ -d "$extracted_dir" ]]; then
        cp -R "$extracted_dir"/* "$jre_dir/"
        echo "JRE installed to $jre_dir"
    else
        echo "ERROR: Expected JRE structure not found"
        exit 1
    fi
}

# Function to find or build JAR
find_jar() {
    local jar_path=""

    # Check in plugin Resources
    if [[ -f "$PODS_ROOT/Resources/$JAR_NAME" ]]; then
        jar_path="$PODS_ROOT/Resources/$JAR_NAME"
    # Check in litertlm-server build
    elif [[ -f "$PLUGIN_ROOT/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar" ]]; then
        jar_path="$PLUGIN_ROOT/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar"
    fi

    echo "$jar_path"
}

# Main setup
if [[ -z "$FRAMEWORKS_PATH" ]]; then
    echo "No frameworks path provided, skipping bundle setup"
    exit 0
fi

# Create directories in app bundle
mkdir -p "$FRAMEWORKS_PATH/../Resources"
mkdir -p "$FRAMEWORKS_PATH/jre"

# Setup JRE
download_jre "$FRAMEWORKS_PATH/jre"

# Copy JAR
JAR_SOURCE=$(find_jar)
if [[ -n "$JAR_SOURCE" && -f "$JAR_SOURCE" ]]; then
    echo "Copying JAR from $JAR_SOURCE..."
    cp "$JAR_SOURCE" "$FRAMEWORKS_PATH/../Resources/$JAR_NAME"
    echo "JAR copied to Resources/"
else
    echo "WARNING: JAR not found. Build litertlm-server first:"
    echo "  cd $PLUGIN_ROOT/litertlm-server && ./gradlew shadowJar"
fi

# Remove quarantine attributes (for development)
xattr -r -d com.apple.quarantine "$FRAMEWORKS_PATH/jre" 2>/dev/null || true
xattr -r -d com.apple.quarantine "$FRAMEWORKS_PATH/../Resources/$JAR_NAME" 2>/dev/null || true

echo "=== Setup complete ==="
