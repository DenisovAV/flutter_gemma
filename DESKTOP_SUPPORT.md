# Flutter Gemma Desktop Support

This document provides detailed instructions for using Flutter Gemma on desktop platforms (macOS, Windows, Linux).

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Supported Platforms](#supported-platforms)
3. [Requirements](#requirements)
4. [Quick Start](#quick-start)
5. [Platform-Specific Setup](#platform-specific-setup)
   - [macOS](#macos)
   - [Windows](#windows)
   - [Linux](#linux)
6. [Building the LiteRT-LM Server](#building-the-litert-lm-server)
7. [Directory Structure](#directory-structure)
8. [Configuration](#configuration)
9. [Troubleshooting](#troubleshooting)
10. [API Reference](#api-reference)

---

## Architecture Overview

Desktop support uses a different architecture than mobile platforms:

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Desktop App                       │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  Dart Layer                             │ │
│  │                                                         │ │
│  │  FlutterGemmaDesktop  ←→  gRPC Client  ←→  localhost   │ │
│  └────────────────────────────────────────────────────────┘ │
│                              ↕                               │
│                         gRPC (TCP)                           │
│                              ↕                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              LiteRT-LM Server (JVM)                     │ │
│  │                                                         │ │
│  │  litertlm-server.jar  ←→  LiteRT-LM JNI  ←→  Native    │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Key Components:**

| Component | Description |
|-----------|-------------|
| `FlutterGemmaDesktop` | Dart implementation using gRPC client |
| `ServerProcessManager` | Manages JVM server lifecycle |
| `LiteRtLmClient` | gRPC client for server communication |
| `litertlm-server.jar` | Kotlin/JVM gRPC server |
| Native Libraries | Platform-specific LiteRT-LM binaries (.dylib/.dll/.so) |

**Why gRPC?**
- LiteRT-LM JVM SDK requires JVM runtime
- Direct FFI binding not possible (Kotlin/JNI layers)
- gRPC provides efficient, typed IPC with streaming support

> **⚠️ Important: Model Format**
>
> Desktop platforms use **LiteRT-LM format only** (`.litertlm` files).
> MediaPipe `.bin` and `.task` models used on mobile/web are **NOT compatible** with desktop.
>
> Supported models must be in LiteRT-LM format. See [AI Edge Model Garden](https://ai.google.dev/edge/litert/models) for compatible models.

---

## Supported Platforms

| Platform | Architecture | GPU Acceleration | Status |
|----------|-------------|------------------|--------|
| macOS | arm64 (Apple Silicon) | Metal | ✅ Ready |
| macOS | x86_64 (Intel) | - | ❌ Not Supported |
| Windows | x86_64 | DirectX 12 | ✅ Ready |
| Windows | arm64 | - | ❌ Not Supported |
| Linux | x86_64 | OpenCL | 🚧 Planned |
| Linux | arm64 | OpenCL | 🚧 Planned |

> **⚠️ Platform Limitations**
>
> LiteRT-LM native libraries are provided by Google and only available for specific architectures:
> - **macOS**: Apple Silicon only (M1/M2/M3/M4). Intel Macs are not supported.
> - **Windows**: x86_64 only. ARM64 Windows is not supported.
> - **Linux**: Both x86_64 and arm64 are supported.
>
> This is a limitation of [Google's LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM), not Flutter Gemma.

---

## Requirements

### All Platforms

- **Flutter**: 3.24.0 or higher
- **Dart**: 3.4.0 or higher
- **Java Runtime**: JRE 21 (automatically downloaded if not present)
- **Model Format**: LiteRT-LM `.litertlm` files only (MediaPipe `.bin`/`.task` not supported)

### macOS

- macOS 10.14 (Mojave) or higher
- Xcode 14+ with Command Line Tools
- CocoaPods 1.11+

### Windows

- Windows 10 (version 1903) or higher
- Visual Studio 2019/2022 with "Desktop development with C++" workload
- PowerShell 5.1+ (included with Windows)
- DirectX Shader Compiler (dxil.dll) - required for GPU acceleration

### Linux

- Ubuntu 20.04+ or equivalent
- GCC 9+ or Clang 10+
- CMake 3.14+

---

## Quick Start

### 1. Add Dependency

```yaml
dependencies:
  flutter_gemma: ^0.11.14
```

### 2. Configure Podfile (macOS only)

Add the following to your `macos/Podfile` in the `post_install` block:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  # Add LiteRT-LM setup script to Runner target
  main_project = installer.aggregate_targets.first.user_project
  runner_target = main_project.targets.find { |t| t.name == 'Runner' }

  if runner_target
    phase_name = 'Setup LiteRT-LM Desktop'
    existing_phase = runner_target.shell_script_build_phases.find { |p| p.name == phase_name }

    unless existing_phase
      phase = runner_target.new_shell_script_build_phase(phase_name)
      phase.shell_script = <<-SCRIPT
PLUGIN_PATH="${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_gemma/macos"
if [ -f "$PLUGIN_PATH/scripts/setup_desktop.sh" ]; then
  sh "$PLUGIN_PATH/scripts/setup_desktop.sh" "$PLUGIN_PATH" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
fi
SCRIPT
      main_project.save
    end
  end
end
```

### 3. Run Your App

```bash
flutter run -d macos   # or -d windows, -d linux
```

The plugin automatically:
- **Builds JAR from source** if JDK 21+ is available, or downloads pre-built JAR as fallback
- Downloads JRE if not present (~50MB, cached)
- Extracts native libraries
- Signs binaries for macOS sandbox
- Starts gRPC server on a free port

### 4. Use the API

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// Install model
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
).fromNetwork('https://example.com/model.litertlm').install();

// Get model instance
final model = await FlutterGemma.getActiveModel(
  maxTokens: 2048,
  preferredBackend: PreferredBackend.gpu,
);

// Create chat session
final chat = await model.createChat();
await chat.addQueryChunk(Message(text: 'Hello!', isUser: true));

// Generate response
await for (final chunk in chat.generateChatResponseAsync()) {
  print(chunk);
}

// Cleanup
await chat.close();
await model.close();
```

---

## Platform-Specific Setup

### macOS

macOS uses CocoaPods with a Podfile hook to run setup after the app bundle is created.

#### Required Podfile Configuration

You **must** add the LiteRT-LM setup hook to your `macos/Podfile`. See [Quick Start](#quick-start) for the complete code.

This is necessary because:
- The setup script needs to copy files into the app bundle
- CocoaPods pod scripts run before the app bundle exists
- The Podfile hook adds a script phase to the Runner target that runs at the right time

#### How It Works

1. Podfile `post_install` hook adds a script phase to the Runner target
2. `macos/scripts/setup_desktop.sh` executes after app bundle is created:
   - **Builds JAR from source** if JDK 21+ is available (checks JAVA_HOME, Homebrew, system)
   - Falls back to downloading pre-built JAR from GitHub Releases
   - Downloads Temurin JRE 21 (cached in `~/Library/Caches/flutter_gemma/jre/`)
   - Extracts native library to `Frameworks/litertlm/`
   - Signs all binaries with sandbox inheritance entitlements

#### App Bundle Structure

```
MyApp.app/
└── Contents/
    ├── MacOS/
    │   └── MyApp (executable)
    ├── Resources/
    │   ├── jre/ (bundled JRE)
    │   │   └── bin/java
    │   ├── litertlm-server.jar
    │   └── java.entitlements
    └── Frameworks/
        └── litertlm/
            └── liblitertlm_jni.so
```

#### Required Entitlements

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<!-- Required for Java subprocess in sandbox -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

The setup script automatically creates `java.entitlements` with sandbox inheritance for the JRE.

#### Troubleshooting macOS

**"java" cannot be opened because the developer cannot be verified:**
```bash
# Remove quarantine from JRE
xattr -r -d com.apple.quarantine ~/path/to/app.app/Contents/Resources/jre
```

**Port already in use:**
```bash
# Kill old Java process
lsof -ti:50051 | xargs kill -9
```
Note: As of v0.11.14, dynamic port allocation prevents this issue.

---

### Windows

Windows uses CMake with a PowerShell build script. No additional configuration required.

#### How It Works

1. `windows/CMakeLists.txt` defines a custom target that runs before build
2. `windows/scripts/setup_desktop.ps1` executes:
   - **Builds JAR from source** if JDK 21+ is available (checks JAVA_HOME, common install locations)
   - Falls back to downloading pre-built JAR from GitHub Releases
   - Downloads Temurin JRE 21 (cached in `%LOCALAPPDATA%\flutter_gemma\jre\`)
   - Extracts DLLs from JAR

#### App Directory Structure

```
MyApp/
├── MyApp.exe (Flutter executable)
├── data/
│   └── litertlm-server.jar
├── jre/
│   └── bin/
│       └── java.exe
└── litertlm/
    ├── LiteRt.dll
    ├── LiteRtGpuAccelerator.dll
    └── ... (other DLLs)
```

#### Build Commands

```powershell
# Development build
flutter run -d windows

# Release build
flutter build windows --release
```

#### Troubleshooting Windows

**PowerShell execution policy error:**
```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**JRE download fails:**
```powershell
# Manually download and extract JRE
$url = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip"
Invoke-WebRequest -Uri $url -OutFile "$env:LOCALAPPDATA\flutter_gemma\jre\jre.zip"
```

**Missing Visual C++ Redistributable:**
```
Download from: https://aka.ms/vs/17/release/vc_redist.x64.exe
```

**dxil.dll Windows Error: 87:**
DirectX Shader Compiler not installed. Required for WebGPU/DirectX 12 GPU acceleration.
```powershell
# Download and install DXC
Invoke-WebRequest -Uri "https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.8.2407/dxc_2024_07_31.zip" -OutFile "$env:TEMP\dxc.zip"
Expand-Archive -Path "$env:TEMP\dxc.zip" -DestinationPath "$env:TEMP\dxc" -Force
Copy-Item "$env:TEMP\dxc\bin\x64\dxil.dll" "C:\Windows\System32\"
Copy-Item "$env:TEMP\dxc\bin\x64\dxcompiler.dll" "C:\Windows\System32\"
```

---

### Linux

Linux uses CMake with a bash build script.

#### How It Works (Planned)

1. `linux/CMakeLists.txt` defines custom commands
2. `linux/scripts/setup_desktop.sh` executes:
   - Downloads Temurin JRE 21
   - Copies JAR and native libraries
   - Sets up library paths

#### App Directory Structure (Planned)

```
my_app/
├── my_app (executable)
├── lib/
│   ├── litertlm/
│   │   └── liblitertlm_jni.so
│   └── jre/
│       └── bin/java
└── data/
    └── litertlm-server.jar
```

#### Environment Variables

```bash
# May be needed for GPU acceleration
export LD_LIBRARY_PATH=/path/to/app/lib/litertlm:$LD_LIBRARY_PATH
```

---

## LiteRT-LM Server JAR

The server JAR (~115MB) is **automatically acquired** during the first build:

1. **Build from source** — If JDK 21+ is detected on your system, the JAR is built locally using Gradle
2. **Download fallback** — If no JDK 21+ is available, a pre-built JAR is downloaded from GitHub Releases

This hybrid approach means:
- Flutter developers (who typically have JDK) get a fresh build
- End users without JDK can still use the plugin via download

### Cache Locations

Built/downloaded files are cached to speed up subsequent builds:
- **macOS**: `~/Library/Caches/flutter_gemma/jar/` and `~/Library/Caches/flutter_gemma/jre/`
- **Windows**: `%LOCALAPPDATA%\flutter_gemma\jar\` and `%LOCALAPPDATA%\flutter_gemma\jre\`

### What's Inside

The JAR includes:
- Kotlin runtime
- gRPC libraries
- LiteRT-LM JVM SDK with bundled native libraries for all platforms

### Manual Build (For Development Only)

If you're modifying the server, you can build it manually:

```bash
cd flutter_gemma/litertlm-server

# macOS/Linux
./gradlew fatJar

# Windows
.\gradlew.bat fatJar
```

Prerequisites: JDK 21+, Gradle 8.0+ (wrapper included)

The locally built JAR will be automatically detected and used instead of downloading.

### Server Startup

The server is started automatically by `ServerProcessManager`:

```
java -Djava.library.path=<natives-dir> \
     -Xmx2048m \
     -jar litertlm-server.jar \
     <port>
```

Arguments:
- `-Djava.library.path`: Directory with native .so/.dll/.dylib files
- `-Xmx2048m`: Maximum heap size (default 2GB)
- `<port>`: gRPC server port (dynamically allocated)

---

## Directory Structure

### Plugin Source Structure

```
flutter_gemma/
├── lib/
│   └── desktop/
│       ├── flutter_gemma_desktop.dart  # Main plugin implementation
│       ├── server_process_manager.dart # JVM process lifecycle
│       ├── grpc_client.dart            # gRPC client wrapper
│       └── desktop_inference_model.dart
├── macos/
│   ├── flutter_gemma.podspec
│   ├── Classes/
│   │   └── FlutterGemmaPlugin.swift    # Placeholder
│   └── scripts/
│       └── setup_desktop.sh            # Build script
├── windows/
│   ├── CMakeLists.txt
│   ├── flutter_gemma_plugin.cpp        # Placeholder
│   └── scripts/
│       └── setup_desktop.ps1           # Build script
├── linux/  (planned)
│   ├── CMakeLists.txt
│   └── scripts/
│       └── setup_desktop.sh
└── litertlm-server/
    ├── build.gradle.kts
    └── src/main/kotlin/
        └── dev/flutterberlin/litertlm/
            ├── Server.kt               # Entry point
            └── LiteRtLmServiceImpl.kt  # gRPC service
```

### Runtime Paths

| Platform | JRE | JAR | Natives |
|----------|-----|-----|---------|
| macOS | `Resources/jre/bin/java` | `Resources/litertlm-server.jar` | `Frameworks/litertlm/` |
| Windows | `jre/bin/java.exe` | `data/litertlm-server.jar` | `litertlm/` |
| Linux | `lib/jre/bin/java` | `data/litertlm-server.jar` | `lib/litertlm/` |

---

## Configuration

### Server Options

```dart
// Start server with custom settings
await ServerProcessManager.instance.start(
  port: 50051,        // Custom port (default: auto-detect free port)
  maxHeapMb: 4096,    // JVM heap size in MB (default: 2048)
);
```

### Model Options

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,                          // Context size
  preferredBackend: PreferredBackend.gpu,   // GPU acceleration
);
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `JAVA_HOME` | Path to JDK/JRE installation | Auto-detect |
| `FLUTTER_GEMMA_PORT` | Fixed gRPC port | Dynamic |
| `FLUTTER_GEMMA_HEAP_MB` | JVM heap size | 2048 |

---

## Troubleshooting

### Common Issues

#### Server Fails to Start

**Symptoms:** `Exception: Server failed to start`

**Solutions:**
1. Check Java is installed: `java -version`
2. Check JAR exists in expected location
3. Check port is not in use
4. Increase heap size for large models

#### Model Initialization Timeout

**Symptoms:** `TimeoutException: Server startup timed out after 30 seconds`

**Solutions:**
1. Model file may be corrupted - redownload
2. Insufficient memory - reduce `maxTokens`
3. GPU driver issues - try `PreferredBackend.cpu`

#### gRPC Connection Failed

**Symptoms:** `GrpcError: UNAVAILABLE`

**Solutions:**
1. Server may have crashed - check logs
2. Firewall blocking localhost - allow port
3. Restart the app

#### Native Library Not Found

**Symptoms:** `UnsatisfiedLinkError: liblitertlm_jni.so`

**Solutions:**
1. Check native library path is correct
2. Re-run build to re-extract natives
3. Check library architecture matches system

### Debug Logging

Enable verbose logging:

```dart
// In your app
import 'package:flutter/foundation.dart';

void main() {
  debugPrint = (String? message, {int? wrapWidth}) {
    print(message);  // See all debug output
  };
  runApp(MyApp());
}
```

Server logs are prefixed with:
- `[ServerProcessManager]` - Process lifecycle
- `[LiteRT-LM Server]` - Server stdout
- `[LiteRT-LM Server ERROR]` - Server stderr

---

## API Reference

### FlutterGemmaDesktop

Main plugin class for desktop platforms.

```dart
class FlutterGemmaDesktop implements FlutterGemmaInterface {
  // Create inference model
  Future<InferenceModel> createModel({
    required ModelType modelType,
    int maxTokens = 1024,
    PreferredBackend preferredBackend = PreferredBackend.cpu,
    bool supportImage = false,
    int maxNumImages = 1,
  });

  // Create embedding model
  Future<EmbeddingModel> createEmbeddingModel();
}
```

### ServerProcessManager

Manages the JVM server lifecycle.

```dart
class ServerProcessManager {
  static ServerProcessManager get instance;

  // Current server port
  int get port;

  // Whether server is running
  bool get isRunning;

  // Start server (auto-finds free port)
  Future<void> start({int? port, int? maxHeapMb});

  // Stop server gracefully
  Future<void> stop();
}
```

### LiteRtLmClient

Low-level gRPC client (usually not used directly).

```dart
class LiteRtLmClient {
  Future<void> connect(String host, int port);
  Future<String> initialize(String modelPath, String backend, int maxTokens);
  Stream<String> chat(String conversationId, String text);
  Future<void> shutdown();
}
```

---

## Performance Tips

1. **Use GPU backend** when available for 2-5x faster inference
2. **Adjust maxTokens** based on your use case (lower = faster)
3. **Reuse chat sessions** instead of creating new ones
4. **Close models** when not needed to free GPU memory
5. **Pre-warm the model** by sending a short query at app start

---

## Security Considerations

1. **gRPC runs on localhost only** - no external network access
2. **Dynamic port allocation** prevents port conflicts
3. **Sandbox inheritance** on macOS maintains security
4. **No code signing required** on Windows/Linux

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

For desktop-specific issues, check:
- `lib/desktop/` - Dart implementation
- `macos/scripts/` - macOS build scripts
- `windows/scripts/` - Windows build scripts
- `litertlm-server/` - Kotlin server

---

## License

Flutter Gemma is licensed under the MIT License. See [LICENSE](LICENSE) for details.

LiteRT-LM is part of Google AI Edge. See licensing terms at:
https://ai.google.dev/edge/litert
