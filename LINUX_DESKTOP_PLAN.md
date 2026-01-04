# Linux Desktop Support Plan for Flutter Gemma

## Overview

Based on Windows implementation experience, this document outlines the plan for Linux desktop support (x86_64 and ARM64).

**Key Insight:** Linux plugin uses `dartPluginClass: FlutterGemmaDesktop` only (no native pluginClass).
This means NO C++ code needed - only CMake for file copying and bash setup script.

**Current Status:**
- ✅ Dart code ready (`FlutterGemmaDesktop` supports Linux - line 250)
- ✅ `ServerProcessManager` has Linux paths (lines 274, 293, 324)
- ✅ pubspec.yaml declares Linux platform with `dartPluginClass: FlutterGemmaDesktop`
- ❌ `linux/` directory missing in plugin (need CMake + setup script)
- ❌ `example/linux/` missing (need `flutter create --platforms=linux .`)

---

## Part 1: Implementation Plan

### 1.1 Architecture (Same as Windows)

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                        │
├─────────────────────────────────────────────────────────────┤
│                  flutter_gemma plugin                        │
│                         │                                    │
│                         ▼                                    │
│              ServerProcessManager                            │
│              (manages JVM process)                           │
│                         │                                    │
│                         ▼                                    │
│    ┌─────────────────────────────────────────┐              │
│    │         JVM Process (JRE 21+)           │              │
│    │    litertlm-server.jar (gRPC server)    │              │
│    │              │                          │              │
│    │              ▼                          │              │
│    │    litertlm_jni.so (native library)     │              │
│    │              │                          │              │
│    │              ▼                          │              │
│    │    GPU: Vulkan/OpenGL (via Dawn/WebGPU) │              │
│    └─────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Required Components

| Component | Windows | Linux x86_64 | Linux ARM64 |
|-----------|---------|--------------|-------------|
| JRE 21+ | Temurin x64 | Temurin x64 | Temurin aarch64 |
| JAR | litertlm-server.jar | Same | Same |
| Native lib | litertlm_jni.dll | litertlm_jni.so | litertlm_jni.so (if available) |
| GPU support | DXC (dxil.dll) | Vulkan SDK? | Vulkan SDK? |

### 1.3 Files to Create/Modify

#### New Files:
```
linux/
├── CMakeLists.txt           # Build configuration (modify existing)
├── scripts/
│   └── setup_desktop.sh     # Linux setup script (like Windows .ps1)
```

#### Modify:
```
lib/
├── desktop/
│   └── server_process_manager.dart  # Add Linux paths
```

### 1.4 Implementation Steps

#### Step 1: Research LiteRT-LM Linux Support
- [ ] Check if linux-x86_64 natives exist in JAR
- [ ] Check if linux-aarch64 natives exist in JAR
- [ ] Identify GPU requirements (Vulkan vs OpenGL)

```bash
# Check natives in JAR
unzip -l litertlm-server.jar | grep -E "linux.*\.so"
```

#### Step 2: Create setup_desktop.sh
```bash
#!/bin/bash
# Similar to Windows PowerShell script but for Linux

# Download JRE (Temurin)
# Architecture detection: x86_64 vs aarch64
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    JRE_ARCH="x64"
    NATIVE_ARCH="linux-x86_64"
elif [ "$ARCH" = "aarch64" ]; then
    JRE_ARCH="aarch64"
    NATIVE_ARCH="linux-aarch64"
fi

# Download from Adoptium
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/..."

# Extract native libraries from JAR
# Copy to output directory
```

#### Step 3: Modify CMakeLists.txt
```cmake
# Add custom target for setup script
add_custom_target(flutter_gemma_setup ALL
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/scripts/setup_desktop.sh"
    "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/flutter_gemma_resources"
  COMMENT "Setting up LiteRT-LM Desktop (JRE, JAR, natives)..."
)

# POST_BUILD: Copy files to bundle
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${CMAKE_BINARY_DIR}/flutter_gemma_resources/jre"
    "${CMAKE_BINARY_DIR}/bundle/jre"
  # ... etc
)
```

#### Step 4: Update ServerProcessManager
```dart
String _getJrePath() {
  if (Platform.isLinux) {
    // Linux: jre is in app bundle
    final execDir = path.dirname(Platform.resolvedExecutable);
    return path.join(execDir, 'jre', 'bin', 'java');
  }
  // ... existing Windows/macOS code
}

String _getNativesPath() {
  if (Platform.isLinux) {
    final execDir = path.dirname(Platform.resolvedExecutable);
    return path.join(execDir, 'litertlm');
  }
  // ...
}
```

#### Step 5: GPU Support Investigation
- Dawn/WebGPU on Linux uses Vulkan
- May need libvulkan.so.1 installed
- NVIDIA: proprietary driver includes Vulkan
- AMD: Mesa includes Vulkan (radv)
- Intel: Mesa includes Vulkan (anv)

---

## Part 2: VM Setup for Testing

### 2.1 Linux x86_64 with GPU (Google Cloud)

```bash
# Create VM with NVIDIA T4 GPU
gcloud compute instances create flutter-gemma-linux-x64 \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB \
  --maintenance-policy=TERMINATE

# Cost: ~$0.50/hour (n1-standard-4 + T4)
```

#### Setup Checklist:
```bash
# 1. Install NVIDIA drivers
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
sudo reboot

# Verify
nvidia-smi

# 2. Install Vulkan
sudo apt install -y vulkan-tools libvulkan1 mesa-vulkan-drivers
vulkaninfo | head -20

# 3. Install Flutter dependencies
sudo apt install -y \
  clang cmake ninja-build \
  libgtk-3-dev \
  liblzma-dev \
  libstdc++-12-dev

# 4. Install Flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:$HOME/flutter/bin"
flutter doctor

# 5. Install Java 21
sudo apt install -y temurin-21-jdk
# Or download from Adoptium

# 6. Clone and test
git clone https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma
git checkout feature/desktop-support
cd example
flutter pub get
flutter run -d linux
```

### 2.2 Linux ARM64 with GPU (More Complex)

**Challenge:** ARM64 Linux VMs with GPU are rare and expensive.

#### Option A: Oracle Cloud (Free Tier - No GPU)
```bash
# ARM64 VM (Ampere A1) - FREE but no GPU
# Good for testing build process, not GPU inference

oci compute instance launch \
  --shape VM.Standard.A1.Flex \
  --shape-config '{"ocpus":4,"memoryInGBs":24}' \
  --image-id <ubuntu-arm64-image> \
  --availability-domain <AD>
```

#### Option B: AWS Graviton with GPU (Expensive)
```bash
# g5g instances - Graviton2 + NVIDIA T4G
# Cost: ~$1.00+/hour

aws ec2 run-instances \
  --instance-type g5g.xlarge \
  --image-id ami-xxxxxxxxx \  # Ubuntu 22.04 ARM64
  --key-name your-key
```

#### Option C: Raspberry Pi 5 + USB GPU (Experimental)
- Raspberry Pi 5 (8GB) - ~$80
- No native GPU but can test CPU inference
- Vulkan via Mesa (llvmpipe software renderer)

#### Option D: NVIDIA Jetson (Best for ARM64 GPU)
- Jetson Orin Nano: ~$500
- Native NVIDIA GPU with Vulkan support
- Best for real ARM64 GPU testing

### 2.3 Recommended Testing Strategy

| Platform | VM/Device | GPU | Cost | Priority |
|----------|-----------|-----|------|----------|
| Linux x64 | GCP n1 + T4 | Yes | $0.50/hr | HIGH |
| Linux ARM64 | Oracle Free A1 | No (CPU only) | Free | MEDIUM |
| Linux ARM64 | AWS g5g.xlarge | Yes | $1.00/hr | LOW (if needed) |
| Linux ARM64 | Jetson Orin | Yes | $500 one-time | OPTIONAL |

### 2.4 GCP Linux x64 VM - Complete Setup Script

```bash
#!/bin/bash
# Save as setup_linux_gpu_vm.sh

set -e

echo "=== Flutter Gemma Linux GPU VM Setup ==="

# Update system
sudo apt update && sudo apt upgrade -y

# Install NVIDIA drivers
echo "Installing NVIDIA drivers..."
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Install Vulkan
echo "Installing Vulkan..."
sudo apt install -y vulkan-tools libvulkan1 mesa-vulkan-drivers nvidia-utils-535

# Install build tools
echo "Installing build tools..."
sudo apt install -y \
  git curl wget unzip \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev

# Install Java 21 (Temurin)
echo "Installing Java 21..."
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo apt-key add -
echo "deb https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt update
sudo apt install -y temurin-21-jdk

# Install Flutter
echo "Installing Flutter..."
cd ~
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:$HOME/flutter/bin"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
flutter doctor

# Verify setup
echo ""
echo "=== Verification ==="
echo "NVIDIA:"
nvidia-smi || echo "NVIDIA driver not loaded (reboot required)"
echo ""
echo "Vulkan:"
vulkaninfo --summary 2>/dev/null || echo "Vulkan not available"
echo ""
echo "Java:"
java -version
echo ""
echo "Flutter:"
flutter --version
echo ""
echo "=== Setup complete! Reboot recommended ==="
echo "After reboot, run: nvidia-smi && vulkaninfo --summary"
```

---

## Part 3: Known Differences from Windows

| Aspect | Windows | Linux |
|--------|---------|-------|
| Native library | .dll | .so |
| GPU API | DirectX 12 | Vulkan |
| GPU shader compiler | DXC (dxil.dll) | SPIR-V (built into Vulkan) |
| Path separator | `\` | `/` |
| Script language | PowerShell | Bash |
| Package manager | N/A | apt/dnf |
| JRE location | Program Files | /usr/lib/jvm or bundled |

---

## Part 4: Open Questions

1. **Does LiteRT-LM include linux-aarch64 natives?**
   - Need to check JAR contents
   - If not, ARM64 Linux may be CPU-only

2. **Vulkan requirements?**
   - Does Dawn/WebGPU need specific Vulkan version?
   - Any runtime libraries needed?

3. **Desktop entry point?**
   - Flutter Linux uses GTK
   - Any special considerations?

4. **Bundled vs System JRE?**
   - Windows: bundled JRE (Temurin)
   - Linux: could use system JRE if 21+ available
   - Bundling ensures consistency

---

## Part 5: Timeline Estimate

| Phase | Tasks |
|-------|-------|
| Research | Check LiteRT-LM Linux support, Vulkan requirements |
| Setup | Create GCP VM, install dependencies |
| Implement | setup_desktop.sh, CMakeLists.txt, Dart changes |
| Test x64 | Build and run on x64 VM with GPU |
| Test ARM64 | Build on ARM64 (CPU), test GPU if available |
| Polish | Error handling, documentation |

---


## Part 8: Files to Create (Copy-Paste Ready)

### 8.1 Create Directory Structure

```bash
cd /path/to/flutter_gemma

# Create plugin linux directory
mkdir -p linux/scripts
mkdir -p linux/include/flutter_gemma
```

### 8.2 linux/CMakeLists.txt

```cmake
# Flutter Gemma Linux Plugin
#
# This CMakeLists.txt sets up the Linux plugin and runs a bash script
# to download JRE, copy JAR, and extract native libraries during build.

cmake_minimum_required(VERSION 3.14)

project(flutter_gemma LANGUAGES CXX)

# This value is used when generating builds using this plugin
set(PLUGIN_NAME "flutter_gemma_plugin")

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "flutter_gemma_plugin.cc"
)

# Apply standard settings
apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# Empty bundled libraries (we copy manually via POST_BUILD)
set(flutter_gemma_bundled_libraries "" PARENT_SCOPE)

# === LiteRT-LM Desktop Setup ===
set(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(SETUP_SCRIPT "${PLUGIN_DIR}/scripts/setup_desktop.sh")
set(SETUP_OUTPUT_DIR "${CMAKE_BINARY_DIR}/flutter_gemma_resources")

# Custom target to run setup script
add_custom_target(flutter_gemma_setup ALL
  COMMAND bash "${SETUP_SCRIPT}" "${PLUGIN_DIR}" "${SETUP_OUTPUT_DIR}"
  WORKING_DIRECTORY "${PLUGIN_DIR}"
  COMMENT "Setting up LiteRT-LM Desktop (JRE, JAR, natives)..."
  VERBATIM
)

add_dependencies(${PLUGIN_NAME} flutter_gemma_setup)

# === POST_BUILD: Copy files to bundle ===
# Linux bundle structure: bundle/data/, bundle/lib/

set(BUNDLE_DIR "${CMAKE_BINARY_DIR}/bundle")

# Copy JAR to data directory
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/data"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${SETUP_OUTPUT_DIR}/data/litertlm-server.jar"
    "${BUNDLE_DIR}/data/litertlm-server.jar"
  COMMENT "Copying litertlm-server.jar to bundle/data/..."
)

# Copy JRE to lib/jre (only if not exists)
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/lib"
  COMMAND bash -c "if [ ! -f '${BUNDLE_DIR}/lib/jre/bin/java' ]; then echo 'Copying JRE...'; cp -r '${SETUP_OUTPUT_DIR}/jre' '${BUNDLE_DIR}/lib/jre'; else echo 'JRE already exists, skipping'; fi"
  COMMENT "Checking/copying JRE to bundle/lib/jre/..."
)

# Copy native libraries to lib/litertlm (only if not exists)
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/lib/litertlm"
  COMMAND bash -c "if [ ! -f '${BUNDLE_DIR}/lib/litertlm/litertlm_jni.so' ]; then echo 'Copying natives...'; cp '${SETUP_OUTPUT_DIR}/litertlm/'* '${BUNDLE_DIR}/lib/litertlm/' 2>/dev/null || true; else echo 'Natives already exist, skipping'; fi"
  COMMENT "Checking/copying native libraries to bundle/lib/litertlm/..."
)
```

### 8.3 linux/flutter_gemma_plugin.cc

```cpp
// Flutter Gemma Linux Plugin
//
// This is a placeholder plugin class for Linux.
// The actual implementation is in Dart (FlutterGemmaDesktop) using gRPC
// to communicate with a Kotlin/JVM server process.

#include "include/flutter_gemma/flutter_gemma_plugin.h"

#include <flutter_linux/flutter_linux.h>

// Placeholder - no actual native implementation needed
// Dart plugin class (FlutterGemmaDesktop) handles everything via gRPC

void flutter_gemma_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // No-op: Desktop implementation is pure Dart using gRPC
  // This function exists only for plugin registration compatibility
}
```

### 8.4 linux/include/flutter_gemma/flutter_gemma_plugin.h

```cpp
// Flutter Gemma Linux Plugin Header
//
// Placeholder header for Linux plugin registration.

#ifndef FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Plugin registration function (required by Flutter plugin system)
void flutter_gemma_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_
```

### 8.5 linux/scripts/setup_desktop.sh

```bash
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
```

### 8.6 Make Script Executable

```bash
chmod +x linux/scripts/setup_desktop.sh
```

### 8.7 Create Example Linux App

```bash
cd flutter_gemma/example
flutter create --platforms=linux .
```

This will create:
```
example/linux/
├── CMakeLists.txt
├── flutter/
│   ├── CMakeLists.txt
│   ├── generated_plugin_registrant.cc
│   ├── generated_plugin_registrant.h
│   └── generated_plugins.cmake
├── main.cc
├── my_application.cc
└── my_application.h
```

---

## Part 9: Verification Checklist

After creating all files:

### 9.1 Verify Plugin Structure
```bash
tree flutter_gemma/linux/
# Expected:
# linux/
# ├── CMakeLists.txt
# ├── flutter_gemma_plugin.cc
# ├── include/
# │   └── flutter_gemma/
# │       └── flutter_gemma_plugin.h
# └── scripts/
#     └── setup_desktop.sh
```

### 9.2 Verify Example Structure
```bash
ls flutter_gemma/example/linux/
# Expected: CMakeLists.txt, flutter/, main.cc, my_application.cc, my_application.h
```

### 9.3 Test Build (on Linux VM)
```bash
cd flutter_gemma/example
flutter pub get
flutter build linux --debug
```

### 9.4 Check Output Files
```bash
ls -la build/linux/x64/debug/bundle/
# Expected:
# data/litertlm-server.jar
# lib/jre/
# lib/litertlm/litertlm_jni.so

# Verify JRE
./build/linux/x64/debug/bundle/lib/jre/bin/java -version
```

### 9.5 Run Application
```bash
flutter run -d linux
```

---

## Part 10: VM Setup Commands (Quick Reference)

### 10.1 Create GCP Linux x64 VM with GPU
```bash
gcloud compute instances create flutter-gemma-linux \
  --zone=us-central1-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=100GB \
  --maintenance-policy=TERMINATE
```

### 10.2 SSH and Setup
```bash
gcloud compute ssh flutter-gemma-linux --zone=us-central1-a

# On VM:
# Install NVIDIA drivers
sudo apt update && sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
sudo reboot

# After reboot - install Flutter dependencies
sudo apt install -y \
  git curl wget unzip \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  vulkan-tools libvulkan1

# Install Flutter
cd ~ && git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor

# Clone and test
git clone https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma && git checkout feature/desktop-support
cd example && flutter pub get && flutter run -d linux
```

### 10.3 Create Oracle ARM64 VM (Free, No GPU)
```bash
# Via Oracle Cloud Console:
# - Shape: VM.Standard.A1.Flex (4 OCPU, 24GB RAM)
# - Image: Ubuntu 22.04 aarch64
# - Free tier eligible
```

---

## Next Steps

1. **Create GCP Linux x64 VM** with T4 GPU (or use existing)
2. **Check LiteRT-LM JAR** for linux natives:
   ```bash
   curl -L -o /tmp/litertlm.jar https://github.com/DenisovAV/flutter_gemma/releases/download/v0.11.16/litertlm-server.jar
   unzip -l /tmp/litertlm.jar | grep -E "linux.*\.so"
   ```
3. **Create linux/ directory** with files from Part 8
4. **Run `flutter create --platforms=linux .`** in example/
5. **Test build on Linux VM**
6. **Test on ARM64** (optional - Oracle free tier)
