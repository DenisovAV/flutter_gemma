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
APP_BUNDLE="${2:-}"

# Skip if not macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping: not macOS"
    exit 0
fi

# Skip if no app bundle path
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "No valid app bundle path provided: $APP_BUNDLE"
    exit 0
fi

echo "App bundle: $APP_BUNDLE"

# Paths
PLUGIN_ROOT="$(cd "$PODS_ROOT/.." && pwd)"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"

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

# JAR settings
JAR_NAME="litertlm-server.jar"
JAR_VERSION="0.12.0"
JAR_URL="https://github.com/DenisovAV/flutter_gemma/releases/download/v${JAR_VERSION}/${JAR_NAME}"
JAR_CHECKSUM="914b9d2526b5673eb810a6080bbc760e537322aaee8e19b9cd49609319cfbdc8"
JAR_CACHE_DIR="$HOME/Library/Caches/flutter_gemma/jar"

echo "Plugin root: $PLUGIN_ROOT"
echo "Resources: $RESOURCES_DIR"
echo "Frameworks: $FRAMEWORKS_DIR"
echo "Architecture: $ARCH ($JRE_ARCH)"

# Create directories
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# === Download and install JRE ===
download_jre() {
    # Check for actual java binary instead of marker file
    if [[ -x "$JRE_DEST/bin/java" ]]; then
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

    echo "JRE installed successfully"
}

# === Check JDK version ===
check_jdk_version() {
    local java_cmd="$1"
    local required_version=21

    if [[ ! -x "$java_cmd" ]]; then
        return 1
    fi

    # Get Java version
    local version_output
    version_output=$("$java_cmd" -version 2>&1 | head -1)

    # Extract major version number
    local major_version
    if [[ "$version_output" =~ \"([0-9]+) ]]; then
        major_version="${BASH_REMATCH[1]}"
    elif [[ "$version_output" =~ ([0-9]+)\. ]]; then
        major_version="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    if [[ "$major_version" -ge "$required_version" ]]; then
        echo "Found JDK $major_version (>= $required_version required)" >&2
        return 0
    else
        echo "JDK $major_version found, but $required_version+ required" >&2
        return 1
    fi
}

# === Find JDK for building ===
find_build_jdk() {
    # Check JAVA_HOME first
    if [[ -n "$JAVA_HOME" ]] && check_jdk_version "$JAVA_HOME/bin/java"; then
        echo "$JAVA_HOME/bin/java"
        return 0
    fi

    # Check common JDK locations on macOS
    local jdk_paths=(
        "/opt/homebrew/opt/openjdk@21/bin/java"
        "/opt/homebrew/opt/openjdk/bin/java"
        "/usr/local/opt/openjdk@21/bin/java"
        "/usr/local/opt/openjdk/bin/java"
        "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java"
        "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home/bin/java"
    )

    for java_path in "${jdk_paths[@]}"; do
        if check_jdk_version "$java_path"; then
            echo "$java_path"
            return 0
        fi
    done

    # Try system java
    if command -v java &>/dev/null && check_jdk_version "$(command -v java)"; then
        command -v java
        return 0
    fi

    return 1
}

# === Build JAR from source ===
build_jar() {
    local gradle_dir="$PLUGIN_ROOT/litertlm-server"
    local gradle_wrapper="$gradle_dir/gradlew"

    if [[ ! -f "$gradle_wrapper" ]]; then
        echo "Gradle wrapper not found at $gradle_wrapper" >&2
        return 1
    fi

    echo "Building JAR from source..." >&2
    cd "$gradle_dir"

    if ! "$gradle_wrapper" fatJar --no-daemon -q; then
        echo "Gradle build failed" >&2
        return 1
    fi

    # Find built JAR
    local built_jar
    built_jar=$(ls -t "$gradle_dir/build/libs/"*-all.jar 2>/dev/null | head -n1)

    if [[ -n "$built_jar" && -f "$built_jar" ]]; then
        echo "JAR built successfully: $built_jar" >&2
        echo "$built_jar"
        return 0
    else
        echo "Built JAR not found" >&2
        return 1
    fi
}

# === Download JAR as fallback ===
download_jar() {
    echo "Downloading JAR from $JAR_URL..." >&2
    mkdir -p "$JAR_CACHE_DIR"

    local cached_jar="$JAR_CACHE_DIR/$JAR_NAME"

    if ! curl -L -o "$cached_jar" "$JAR_URL" --fail --retry 3 --progress-bar; then
        echo "ERROR: Failed to download JAR" >&2
        rm -f "$cached_jar"
        return 1
    fi

    # Verify checksum
    if [[ -n "$JAR_CHECKSUM" ]]; then
        echo "Verifying checksum..." >&2
        local actual_checksum
        actual_checksum=$(shasum -a 256 "$cached_jar" | awk '{print $1}')
        if [[ "$actual_checksum" != "$JAR_CHECKSUM" ]]; then
            rm -f "$cached_jar"
            echo "ERROR: JAR checksum mismatch!" >&2
            echo "  Expected: $JAR_CHECKSUM" >&2
            echo "  Got: $actual_checksum" >&2
            return 1
        fi
        echo "Checksum verified" >&2
    fi

    echo "$cached_jar"
    return 0
}

# === Setup JAR (build or download) ===
setup_jar() {
    local jar_dest="$RESOURCES_DIR/$JAR_NAME"

    if [[ -f "$jar_dest" ]]; then
        echo "JAR already in app bundle"
        return 0
    fi

    echo "Setting up LiteRT-LM Server JAR..."

    local jar_source=""

    # 1. Check for locally built JAR first
    local local_jar
    local_jar=$(ls -t "$PLUGIN_ROOT/litertlm-server/build/libs/"*-all.jar 2>/dev/null | head -n1)
    if [[ -n "$local_jar" && -f "$local_jar" ]]; then
        echo "Using locally built JAR: $local_jar"
        jar_source="$local_jar"
    fi

    # 2. Try to build if JDK 21+ available
    if [[ -z "$jar_source" ]]; then
        echo "Checking for JDK 21+..."
        local jdk_path
        if jdk_path=$(find_build_jdk 2>/dev/null); then
            echo "Using JDK: $jdk_path"
            export JAVA_HOME="$(dirname "$(dirname "$jdk_path")")"
            if jar_source=$(build_jar); then
                echo "Built JAR successfully"
            else
                echo "Build failed, will try download..."
                jar_source=""
            fi
        else
            echo "JDK 21+ not found, will download JAR..."
        fi
    fi

    # 3. Download as fallback
    if [[ -z "$jar_source" ]]; then
        # Check cache first
        local cached_jar="$JAR_CACHE_DIR/$JAR_NAME"
        if [[ -f "$cached_jar" ]]; then
            echo "Using cached JAR"
            jar_source="$cached_jar"
        else
            if jar_source=$(download_jar); then
                echo "Downloaded JAR successfully"
            else
                echo "ERROR: Could not obtain JAR (build failed, download failed)"
                exit 1
            fi
        fi
    fi

    # Copy to app bundle
    echo "Copying JAR to app bundle..."
    cp "$jar_source" "$jar_dest"

    echo "JAR installed successfully"
}

# === Extract and sign native libraries ===
extract_natives() {
    local NATIVES_DIR="$FRAMEWORKS_DIR/litertlm"

    # Check if already extracted (look for actual .so files, not marker)
    if ls "$NATIVES_DIR"/*.so 1> /dev/null 2>&1; then
        echo "Native libraries already installed"
        return 0
    fi

    # Detect architecture for native library path
    local NATIVE_ARCH
    if [[ "$ARCH" == "arm64" ]]; then
        NATIVE_ARCH="darwin-aarch64"
    else
        # Intel Mac (x86_64) is NOT supported by LiteRT-LM
        # Google only provides native libraries for Apple Silicon
        echo "WARNING: Intel Mac (x86_64) is not supported by LiteRT-LM"
        echo "  LiteRT-LM only provides native libraries for Apple Silicon (arm64)"
        echo "  Desktop support requires an Apple Silicon Mac (M1/M2/M3/M4)"
        echo "  See: https://github.com/google-ai-edge/LiteRT-LM"
        return 0
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
setup_jar
extract_natives
remove_quarantine
sign_jre

echo "=== Setup complete ==="
