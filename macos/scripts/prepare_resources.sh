#!/bin/bash
# LiteRT-LM Resource Preparation Script
# Called by CocoaPods prepare_command during pod install
# Downloads/builds JAR and JRE, places in Resources/ for bundling

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PLUGIN_DIR/Resources"

echo "=== LiteRT-LM Resource Preparation ==="
echo "Plugin dir: $PLUGIN_DIR"
echo "Resources dir: $RESOURCES_DIR"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    JRE_ARCH="aarch64"
else
    JRE_ARCH="x64"
fi
echo "Architecture: $ARCH ($JRE_ARCH)"

# JRE settings
JRE_VERSION="21.0.5+11"
JRE_ARCHIVE="OpenJDK21U-jre_${JRE_ARCH}_mac_hotspot_${JRE_VERSION/+/_}.tar.gz"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JRE_VERSION}/${JRE_ARCHIVE}"
JRE_CACHE_DIR="$HOME/Library/Caches/flutter_gemma/jre"

# SHA256 checksums from Adoptium
JRE_CHECKSUM_AARCH64="12249a1c5386957c93fc372260c483ae921b1ec6248a5136725eabd0abc07f93"
JRE_CHECKSUM_X64="0e0dcb571f7bf7786c111fe066932066d9eab080c9f86d8178da3e564324ee81"

# JAR settings
JAR_NAME="litertlm-server.jar"
JAR_VERSION="0.12.0"
JAR_URL="https://github.com/DenisovAV/flutter_gemma/releases/download/v${JAR_VERSION}/${JAR_NAME}"
JAR_CHECKSUM="914b9d2526b5673eb810a6080bbc760e537322aaee8e19b9cd49609319cfbdc8"
JAR_CACHE_DIR="$HOME/Library/Caches/flutter_gemma/jar"

# Create Resources directory
mkdir -p "$RESOURCES_DIR"

# === Check JDK version ===
check_jdk_version() {
    local java_cmd="$1"
    local required_version=21

    if [[ ! -x "$java_cmd" ]]; then
        return 1
    fi

    local version_output
    version_output=$("$java_cmd" -version 2>&1 | head -1)

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
    if [[ -n "$JAVA_HOME" ]] && check_jdk_version "$JAVA_HOME/bin/java"; then
        echo "$JAVA_HOME/bin/java"
        return 0
    fi

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

    if command -v java &>/dev/null && check_jdk_version "$(command -v java)"; then
        command -v java
        return 0
    fi

    return 1
}

# === Build JAR from source ===
build_jar() {
    local gradle_dir="$PLUGIN_DIR/../litertlm-server"
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

# === Download JAR ===
download_jar() {
    echo "Downloading JAR from $JAR_URL..." >&2
    mkdir -p "$JAR_CACHE_DIR"

    local cached_jar="$JAR_CACHE_DIR/$JAR_NAME"

    if [[ -f "$cached_jar" ]]; then
        echo "Using cached JAR" >&2
        echo "$cached_jar"
        return 0
    fi

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
            return 1
        fi
        echo "Checksum verified" >&2
    fi

    echo "$cached_jar"
    return 0
}

# === Setup JAR ===
setup_jar() {
    local jar_dest="$RESOURCES_DIR/$JAR_NAME"

    if [[ -f "$jar_dest" ]]; then
        echo "JAR already in Resources"
        return 0
    fi

    echo "Setting up LiteRT-LM Server JAR..."

    local jar_source=""

    # 1. Check for locally built JAR
    local local_jar
    local_jar=$(ls -t "$PLUGIN_DIR/../litertlm-server/build/libs/"*-all.jar 2>/dev/null | head -n1)
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
        if jar_source=$(download_jar); then
            echo "Downloaded JAR successfully"
        else
            echo "ERROR: Could not obtain JAR"
            exit 1
        fi
    fi

    # Copy to Resources
    echo "Copying JAR to Resources..."
    cp "$jar_source" "$jar_dest"
    echo "JAR installed: $(du -h "$jar_dest" | cut -f1)"
}

# === Download and setup JRE ===
setup_jre() {
    local jre_dest="$RESOURCES_DIR/jre"
    local jre_marker="$jre_dest/.jre_installed"

    if [[ -f "$jre_marker" ]]; then
        echo "JRE already in Resources"
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
            rm -f "$archive"
            exit 1
        fi

        # Verify checksum
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
                exit 1
            fi
            echo "Checksum verified"
        fi
    else
        echo "Using cached JRE archive"
    fi

    # Extract if needed
    if [[ ! -f "$extraction_marker" ]]; then
        echo "Extracting JRE..."
        rm -rf "$extracted"
        tar -xzf "$archive" -C "$JRE_CACHE_DIR"
        touch "$extraction_marker"
    fi

    # Copy to Resources
    echo "Copying JRE to Resources..."
    mkdir -p "$jre_dest"
    cp -R "$extracted/Contents/Home/"* "$jre_dest/"
    touch "$jre_marker"

    echo "JRE installed: $(du -sh "$jre_dest" | cut -f1)"
}

# === Extract native libraries ===
extract_natives() {
    local natives_dir="$RESOURCES_DIR/litertlm"
    local natives_marker="$natives_dir/.natives_installed"

    if [[ -f "$natives_marker" ]]; then
        echo "Native libraries already extracted"
        return 0
    fi

    local jar_path="$RESOURCES_DIR/$JAR_NAME"
    if [[ ! -f "$jar_path" ]]; then
        echo "JAR not found, skipping native extraction"
        return 0
    fi

    # Detect native library path
    local NATIVE_ARCH
    if [[ "$ARCH" == "arm64" ]]; then
        NATIVE_ARCH="darwin-aarch64"
    else
        NATIVE_ARCH="darwin-x86_64"
    fi
    local NATIVE_PATH="com/google/ai/edge/litertlm/jni/$NATIVE_ARCH"

    echo "Extracting native libraries..."
    echo "  Native path: $NATIVE_PATH"

    rm -rf "$natives_dir"
    mkdir -p "$natives_dir"

    # Extract to temp directory
    local temp_dir
    temp_dir=$(mktemp -d)

    unzip -o "$jar_path" "$NATIVE_PATH/*" -d "$temp_dir" 2>/dev/null || {
        echo "WARNING: Could not extract native libraries"
        rm -rf "$temp_dir"
        return 0
    }

    # Copy native libraries
    local extracted_dir="$temp_dir/$NATIVE_PATH"
    if [[ -d "$extracted_dir" ]]; then
        find "$extracted_dir" -type f \( -name "*.so" -o -name "*.dylib" \) | while read -r file; do
            cp "$file" "$natives_dir/"
            echo "  Extracted: $(basename "$file")"
        done
    fi

    rm -rf "$temp_dir"
    touch "$natives_marker"
    echo "Native libraries extracted"
}

# === Create entitlements file ===
create_entitlements() {
    local entitlements_file="$RESOURCES_DIR/java.entitlements"

    if [[ -f "$entitlements_file" ]]; then
        return 0
    fi

    echo "Creating Java entitlements..."
    cat > "$entitlements_file" << 'ENTITLEMENTS'
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
}

# === Main ===
echo ""
setup_jar
echo ""
setup_jre
echo ""
extract_natives
echo ""
create_entitlements
echo ""
echo "=== Resource preparation complete ==="
echo "Resources ready in: $RESOURCES_DIR"
ls -la "$RESOURCES_DIR"
