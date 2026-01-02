#!/bin/bash
# LiteRT-LM Desktop Setup Script for Flutter Gemma
# Automatically downloads JRE and copies JAR to app bundle
#
# This script runs as an Xcode Build Phase

set -e

echo "=== LiteRT-LM Desktop Setup ==="

# Paths from Xcode environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
APP_BUNDLE="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"

# JRE settings
JRE_VERSION="21.0.5+11"
JRE_CACHE_DIR="$HOME/.cache/flutter_gemma/jre"
# Put JRE in Resources (not Frameworks) to avoid code signing issues
JRE_DEST="${RESOURCES_DIR}/jre"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    JRE_ARCH="aarch64"
else
    JRE_ARCH="x64"
fi

JRE_ARCHIVE="OpenJDK21U-jre_${JRE_ARCH}_mac_hotspot_${JRE_VERSION/+/_}.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JRE_VERSION}/${JRE_ARCHIVE}"

JAR_NAME="litertlm-server.jar"
JAR_SOURCE="${PLUGIN_DIR}/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar"
JAR_ALT_SOURCE="${PLUGIN_DIR}/macos/Resources/litertlm-server.jar"

echo "Project: $PROJECT_DIR"
echo "Plugin: $PLUGIN_DIR"
echo "App bundle: $APP_BUNDLE"
echo "Architecture: $ARCH ($JRE_ARCH)"

# Skip if not building for macOS
if [[ -z "$BUILT_PRODUCTS_DIR" ]]; then
    echo "Not running in Xcode build context, skipping"
    exit 0
fi

# Create directories
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# === Download and install JRE ===
download_jre() {
    if [[ -f "$JRE_DEST/bin/java" ]]; then
        echo "JRE already installed in app bundle"
        return 0
    fi

    echo "Setting up JRE..."
    mkdir -p "$JRE_CACHE_DIR"

    local archive="$JRE_CACHE_DIR/$JRE_ARCHIVE"
    local extracted="$JRE_CACHE_DIR/jdk-${JRE_VERSION}-jre"

    # Download if not cached
    if [[ ! -f "$archive" ]]; then
        echo "Downloading JRE from $JRE_URL..."
        curl -L -o "$archive" "$JRE_URL"
    else
        echo "Using cached JRE archive"
    fi

    # Extract if needed
    if [[ ! -d "$extracted" ]]; then
        echo "Extracting JRE..."
        tar -xzf "$archive" -C "$JRE_CACHE_DIR"
    fi

    # Copy to app bundle
    echo "Copying JRE to app bundle..."
    mkdir -p "$JRE_DEST"
    cp -R "$extracted/Contents/Home/"* "$JRE_DEST/"

    echo "JRE installed successfully"
}

# === Copy JAR ===
copy_jar() {
    local jar_dest="$RESOURCES_DIR/$JAR_NAME"

    if [[ -f "$jar_dest" ]]; then
        echo "JAR already in app bundle"
        return 0
    fi

    if [[ -f "$JAR_SOURCE" ]]; then
        echo "Copying JAR from build output..."
        cp "$JAR_SOURCE" "$jar_dest"
    elif [[ -f "$JAR_ALT_SOURCE" ]]; then
        echo "Copying JAR from plugin resources..."
        cp "$JAR_ALT_SOURCE" "$jar_dest"
    else
        echo "ERROR: JAR not found!"
        echo "  Expected at: $JAR_SOURCE"
        echo "  Or at: $JAR_ALT_SOURCE"
        echo ""
        echo "Build the server first:"
        echo "  cd $PLUGIN_DIR/litertlm-server && ./gradlew shadowJar"
        exit 1
    fi

    echo "JAR copied successfully"
}

# === Extract and sign native libraries ===
extract_natives() {
    local NATIVES_DIR="$FRAMEWORKS_DIR/litertlm"

    # Detect architecture for native library path
    local NATIVE_PATH
    if [[ "$ARCH" == "arm64" ]]; then
        NATIVE_PATH="com/google/ai/edge/litertlm/jni/darwin-aarch64/liblitertlm_jni.so"
    else
        NATIVE_PATH="com/google/ai/edge/litertlm/jni/darwin-x86_64/liblitertlm_jni.so"
    fi

    local jar_path="$RESOURCES_DIR/$JAR_NAME"

    if [[ ! -f "$jar_path" ]]; then
        echo "JAR not found, skipping native extraction"
        return 0
    fi

    # Create natives directory
    mkdir -p "$NATIVES_DIR"

    # Extract native library from JAR
    echo "Extracting native library from JAR..."
    unzip -o -j "$jar_path" "$NATIVE_PATH" -d "$NATIVES_DIR" 2>/dev/null || {
        echo "WARNING: Could not extract native library (may not exist for this architecture)"
        return 0
    }

    # Remove quarantine and sign
    if [[ -f "$NATIVES_DIR/liblitertlm_jni.so" ]]; then
        echo "Signing native library..."
        xattr -r -d com.apple.quarantine "$NATIVES_DIR/liblitertlm_jni.so" 2>/dev/null || true
        codesign --force --sign - "$NATIVES_DIR/liblitertlm_jni.so"
        echo "Native library extracted and signed: $NATIVES_DIR/liblitertlm_jni.so"
    fi
}

# === Remove quarantine (for development) ===
remove_quarantine() {
    echo "Removing quarantine attributes..."
    xattr -r -d com.apple.quarantine "$JRE_DEST" 2>/dev/null || true
    xattr -r -d com.apple.quarantine "$RESOURCES_DIR/$JAR_NAME" 2>/dev/null || true
}

# === Sign JRE binaries (for development) ===
sign_jre() {
    echo "Signing JRE binaries..."

    # Create child entitlements for sandbox inheritance
    # See: https://developer.apple.com/forums/thread/706390
    local CHILD_ENTITLEMENTS="$RESOURCES_DIR/java.entitlements"
    cat > "$CHILD_ENTITLEMENTS" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.inherit</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

    # Sign all dylibs first (without entitlements)
    find "$JRE_DEST" -type f -name "*.dylib" | while read -r file; do
        codesign --force --sign - "$file" 2>/dev/null || true
    done

    # Sign java executable with sandbox inheritance entitlements
    if [[ -f "$JRE_DEST/bin/java" ]]; then
        echo "Signing java with sandbox inheritance entitlements..."
        codesign --force --sign - --entitlements "$CHILD_ENTITLEMENTS" "$JRE_DEST/bin/java"
    fi

    # Sign other executables with inheritance entitlements
    find "$JRE_DEST/bin" -type f -perm +111 ! -name "java" | while read -r file; do
        if file "$file" | grep -q "Mach-O"; then
            codesign --force --sign - --entitlements "$CHILD_ENTITLEMENTS" "$file" 2>/dev/null || true
        fi
    done

    echo "JRE signed with sandbox inheritance"
}

# Run setup
download_jre
copy_jar
extract_natives
remove_quarantine
sign_jre

echo "=== Setup complete ==="
