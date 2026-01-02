#!/bin/bash
# LiteRT-LM Desktop Setup Script for Flutter Gemma Plugin
# Version: 0.11.14
# Downloads JRE, copies JAR, extracts natives, and signs for macOS sandbox
#
# Usage: setup_desktop.sh <PODS_TARGET_SRCROOT> <FRAMEWORKS_PATH>
# Called by CocoaPods script_phase during pod installation

set -e

echo "=== LiteRT-LM Desktop Setup (macOS) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PODS_ROOT="${1:-$SCRIPT_DIR/..}"
FRAMEWORKS_PATH="${2:-}"

# Skip if not macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping: not macOS"
    exit 0
fi

# Skip if no frameworks path (not building app bundle)
if [[ -z "$FRAMEWORKS_PATH" ]]; then
    echo "No frameworks path provided, skipping bundle setup"
    exit 0
fi

# Paths
PLUGIN_ROOT="$(cd "$PODS_ROOT/.." && pwd)"
RESOURCES_DIR="$FRAMEWORKS_PATH/../Resources"
FRAMEWORKS_DIR="$FRAMEWORKS_PATH"

# JRE settings
JRE_VERSION="21.0.5+11"
# Use macOS standard cache location (~/Library/Caches per Apple guidelines)
JRE_CACHE_DIR="$HOME/Library/Caches/flutter_gemma/jre"
JRE_DEST="$RESOURCES_DIR/jre"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    JRE_ARCH="aarch64"
else
    JRE_ARCH="x64"
fi

JRE_ARCHIVE="OpenJDK21U-jre_${JRE_ARCH}_mac_hotspot_${JRE_VERSION/+/_}.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JRE_VERSION}/${JRE_ARCHIVE}"

# SHA256 checksums from Adoptium (https://adoptium.net/temurin/releases/)
# Note: Using simple variables instead of associative arrays for bash 3.x compatibility (macOS default)
JRE_CHECKSUM_AARCH64="12249a1c5386957c93fc372260c483ae921b1ec6248a5136725eabd0abc07f93"
JRE_CHECKSUM_X64="0e0dcb571f7bf7786c111fe066932066d9eab080c9f86d8178da3e564324ee81"

JAR_NAME="litertlm-server.jar"

echo "Plugin root: $PLUGIN_ROOT"
echo "Resources: $RESOURCES_DIR"
echo "Frameworks: $FRAMEWORKS_DIR"
echo "Architecture: $ARCH ($JRE_ARCH)"

# Create directories
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# === Download and install JRE ===
download_jre() {
    local jre_marker="$JRE_DEST/.jre_installed"

    # Check for marker file to detect complete installation
    if [[ -f "$jre_marker" ]]; then
        echo "JRE already installed in app bundle"
        return 0
    fi

    echo "Setting up JRE..."
    mkdir -p "$JRE_CACHE_DIR"

    local archive="$JRE_CACHE_DIR/$JRE_ARCHIVE"
    local extracted="$JRE_CACHE_DIR/jdk-${JRE_VERSION}-jre"
    local extraction_marker="$extracted/.extracted"

    # Download if not cached
    if [[ ! -f "$archive" ]]; then
        echo "Downloading JRE from $JRE_URL..."
        if ! curl -L -o "$archive" "$JRE_URL" --fail --retry 3 --progress-bar; then
            echo "ERROR: Failed to download JRE"
            rm -f "$archive"  # Remove partial download
            exit 1
        fi

        # Verify checksum (using simple variables for bash 3.x compatibility)
        local expected_checksum=""
        if [[ "$JRE_ARCH" == "aarch64" ]]; then
            expected_checksum="$JRE_CHECKSUM_AARCH64"
        else
            expected_checksum="$JRE_CHECKSUM_X64"
        fi
        if [[ -n "$expected_checksum" ]]; then
            echo "Verifying checksum..."
            local actual_checksum
            actual_checksum=$(shasum -a 256 "$archive" | awk '{print $1}')
            if [[ "$actual_checksum" != "$expected_checksum" ]]; then
                rm -f "$archive"
                echo "ERROR: JRE checksum mismatch!"
                echo "  Expected: $expected_checksum"
                echo "  Got: $actual_checksum"
                exit 1
            fi
            echo "Checksum verified"
        else
            echo "WARNING: Checksum not available for $JRE_ARCH, skipping verification"
        fi
    else
        echo "Using cached JRE archive"
    fi

    # Extract if needed (check marker file, not just directory existence)
    if [[ ! -f "$extraction_marker" ]]; then
        echo "Extracting JRE..."
        # Remove partial extraction if exists
        rm -rf "$extracted"
        tar -xzf "$archive" -C "$JRE_CACHE_DIR"
        # Mark extraction complete
        touch "$extraction_marker"
    fi

    # Copy to app bundle
    echo "Copying JRE to app bundle..."
    mkdir -p "$JRE_DEST"
    cp -R "$extracted/Contents/Home/"* "$JRE_DEST/"

    # Create marker file to indicate complete installation
    touch "$jre_marker"

    echo "JRE installed successfully"
}

# === Copy JAR ===
copy_jar() {
    local jar_dest="$RESOURCES_DIR/$JAR_NAME"

    if [[ -f "$jar_dest" ]]; then
        echo "JAR already in app bundle"
        return 0
    fi

    # Check in plugin Resources first
    local jar_source=""
    if [[ -f "$PODS_ROOT/Resources/$JAR_NAME" ]]; then
        jar_source="$PODS_ROOT/Resources/$JAR_NAME"
    fi

    # Check in litertlm-server build (version-agnostic using glob)
    if [[ -z "$jar_source" ]]; then
        local gradle_libs_dir="$PLUGIN_ROOT/litertlm-server/build/libs"
        if [[ -d "$gradle_libs_dir" ]]; then
            # Find latest fat JAR (version-agnostic)
            local fat_jar
            fat_jar=$(ls -t "$gradle_libs_dir"/*-all.jar 2>/dev/null | head -n1)
            if [[ -n "$fat_jar" && -f "$fat_jar" ]]; then
                jar_source="$fat_jar"
            fi
        fi
    fi

    if [[ -n "$jar_source" && -f "$jar_source" ]]; then
        echo "Copying JAR from $jar_source..."
        cp "$jar_source" "$jar_dest"
        echo "JAR copied successfully"
        return 0
    else
        echo "ERROR: JAR not found!"
        echo "  Expected at: $PODS_ROOT/Resources/$JAR_NAME"
        echo "  Or at: $PLUGIN_ROOT/litertlm-server/build/libs/*-all.jar"
        echo ""
        echo "Build the server first:"
        echo "  cd $PLUGIN_ROOT/litertlm-server && ./gradlew fatJar"
        return 1
    fi
}

# === Extract and sign native libraries ===
extract_natives() {
    local NATIVES_DIR="$FRAMEWORKS_DIR/litertlm"
    local natives_marker="$NATIVES_DIR/.natives_installed"

    # Check if already extracted and signed
    if [[ -f "$natives_marker" ]]; then
        echo "Native libraries already installed"
        return 0
    fi

    # Detect architecture for native library path
    local NATIVE_ARCH
    if [[ "$ARCH" == "arm64" ]]; then
        NATIVE_ARCH="darwin-aarch64"
    else
        NATIVE_ARCH="darwin-x86_64"
    fi
    local NATIVE_PATH="com/google/ai/edge/litertlm/jni/$NATIVE_ARCH"

    local jar_path="$RESOURCES_DIR/$JAR_NAME"

    if [[ ! -f "$jar_path" ]]; then
        echo "JAR not found, skipping native extraction"
        return 0
    fi

    echo "Extracting native libraries from JAR..."
    echo "  Native path: $NATIVE_PATH"

    # Create natives directory (remove old signed files if exist)
    rm -rf "$NATIVES_DIR"
    mkdir -p "$NATIVES_DIR"

    # Extract to temp directory first (for path traversal protection)
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    # Extract native libraries from JAR
    unzip -o "$jar_path" "$NATIVE_PATH/*" -d "$temp_dir" 2>/dev/null || {
        echo "WARNING: Could not extract native libraries (may not exist for this architecture)"
        rm -rf "$temp_dir"
        return 0
    }

    # Validate and copy only .so/.dylib files from expected location (path traversal protection)
    local extracted_dir="$temp_dir/$NATIVE_PATH"
    if [[ -d "$extracted_dir" ]]; then
        local allowed_path
        allowed_path=$(cd "$extracted_dir" && pwd)

        find "$extracted_dir" -type f \( -name "*.so" -o -name "*.dylib" \) | while read -r file; do
            local resolved_path
            resolved_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")

            # Validate path is within expected directory (prevent path traversal)
            if [[ "$resolved_path" == "$allowed_path"/* ]]; then
                cp "$file" "$NATIVES_DIR/"
                local filename
                filename=$(basename "$file")
                echo "  Extracted: $filename"

                # Remove quarantine and sign
                xattr -r -d com.apple.quarantine "$NATIVES_DIR/$filename" 2>/dev/null || true
                codesign --force --sign - "$NATIVES_DIR/$filename"
            else
                echo "WARNING: Skipping suspicious path: $resolved_path"
            fi
        done
    else
        echo "WARNING: Native libraries not found in JAR at path: $NATIVE_PATH"
    fi

    # Cleanup
    rm -rf "$temp_dir"
    trap - EXIT

    # Create marker file to indicate complete installation
    touch "$natives_marker"

    echo "Native libraries extracted and signed"
}

# === Remove quarantine (for development) ===
remove_quarantine() {
    echo "Removing quarantine attributes..."
    xattr -r -d com.apple.quarantine "$JRE_DEST" 2>/dev/null || true
    xattr -r -d com.apple.quarantine "$RESOURCES_DIR/$JAR_NAME" 2>/dev/null || true
}

# === Sign JRE binaries with sandbox inheritance ===
sign_jre() {
    echo "Signing JRE binaries..."

    # Create child entitlements for sandbox inheritance
    # Required for Java to run as subprocess in sandboxed macOS app
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

if ! copy_jar; then
    echo "ERROR: Build cannot continue without JAR file"
    exit 1
fi

extract_natives
remove_quarantine
sign_jre

echo "=== Setup complete ==="
