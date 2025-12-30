# Flutter Gemma Desktop: LiteRT-LM через Kotlin/JVM

## Цель

Добавить поддержку `.litertlm` моделей на desktop платформах (macOS, Windows, Linux) через Kotlin/JVM API.

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter Desktop App                         │
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   macOS      │    │   Windows    │    │    Linux     │       │
│  │   Runner     │    │   Runner     │    │   Runner     │       │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘       │
│         │                   │                   │                │
│         └───────────────────┼───────────────────┘                │
│                             │                                    │
│                    ┌────────▼────────┐                          │
│                    │   Dart Layer    │                          │
│                    │                 │                          │
│                    │ LiteRtLmDesktop │                          │
│                    └────────┬────────┘                          │
│                             │                                    │
│                      Socket/gRPC                                 │
│                             │                                    │
└─────────────────────────────┼───────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                    LiteRT-LM Server (JVM)                        │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              litertlm-server.jar (Kotlin)                │    │
│  │                                                          │    │
│  │  - gRPC/WebSocket server                                │    │
│  │  - Engine initialization                                 │    │
│  │  - Conversation management                               │    │
│  │  - Streaming responses                                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                             │                                    │
│                            JNI                                   │
│                             │                                    │
│         ┌───────────────────┼───────────────────┐               │
│         ▼                   ▼                   ▼               │
│  ┌────────────┐      ┌────────────┐      ┌────────────┐        │
│  │   macOS    │      │  Windows   │      │   Linux    │        │
│  │   .dylib   │      │   .dll     │      │   .so      │        │
│  │   Metal    │      │   DX12     │      │  OpenCL    │        │
│  └────────────┘      └────────────┘      └────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Фазы реализации

### Фаза 1: Kotlin Server (2-3 дня)

**Цель**: Создать standalone Kotlin приложение-сервер для LiteRT-LM.

#### 1.1 Структура проекта

```
litertlm-server/
├── build.gradle.kts
├── settings.gradle.kts
├── src/
│   └── main/
│       └── kotlin/
│           └── dev/flutterberlin/litertlm/
│               ├── Server.kt           # Entry point
│               ├── LiteRtLmService.kt  # gRPC service
│               ├── EngineManager.kt    # Engine lifecycle
│               └── proto/
│                   └── litertlm.proto  # gRPC schema
└── natives/
    ├── macos/
    ├── windows/
    └── linux/
```

#### 1.2 build.gradle.kts

```kotlin
plugins {
    kotlin("jvm") version "1.9.0"
    id("com.google.protobuf") version "0.9.4"
    application
}

dependencies {
    // LiteRT-LM
    implementation("com.google.ai.edge:litertlm:0.9.0-alpha01")

    // gRPC
    implementation("io.grpc:grpc-kotlin-stub:1.4.1")
    implementation("io.grpc:grpc-netty-shaded:1.60.0")
    implementation("com.google.protobuf:protobuf-kotlin:3.25.1")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
}

application {
    mainClass.set("dev.flutterberlin.litertlm.ServerKt")
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = "dev.flutterberlin.litertlm.ServerKt"
    }
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
```

#### 1.3 Proto Schema

```protobuf
// proto/litertlm.proto
syntax = "proto3";

package litertlm;

option java_package = "dev.flutterberlin.litertlm.proto";

service LiteRtLmService {
  // Initialize engine with model
  rpc Initialize(InitializeRequest) returns (InitializeResponse);

  // Create new conversation
  rpc CreateConversation(CreateConversationRequest) returns (CreateConversationResponse);

  // Send message and stream response
  rpc Chat(ChatRequest) returns (stream ChatResponse);

  // Close conversation
  rpc CloseConversation(CloseConversationRequest) returns (CloseConversationResponse);

  // Shutdown engine
  rpc Shutdown(ShutdownRequest) returns (ShutdownResponse);
}

message InitializeRequest {
  string model_path = 1;
  string backend = 2;  // "cpu", "gpu"
  int32 max_tokens = 3;
  bool enable_vision = 4;
  bool enable_audio = 5;
}

message InitializeResponse {
  bool success = 1;
  string error = 2;
}

message CreateConversationRequest {
  string system_message = 1;
  repeated ToolDefinition tools = 2;
  SamplerConfig sampler_config = 3;
  bool enable_constrained_decoding = 4;
}

message ToolDefinition {
  string name = 1;
  string description = 2;
  repeated ToolParameter parameters = 3;
}

message ToolParameter {
  string name = 1;
  string type = 2;
  string description = 3;
  bool required = 4;
}

message SamplerConfig {
  int32 top_k = 1;
  float top_p = 2;
  float temperature = 3;
}

message CreateConversationResponse {
  string conversation_id = 1;
  string error = 2;
}

message ChatRequest {
  string conversation_id = 1;
  string text = 2;
  bytes image = 3;  // Optional image
  bytes audio = 4;  // Optional audio
}

message ChatResponse {
  string text = 1;           // Partial or complete text
  bool done = 2;             // Is generation complete
  ToolCall tool_call = 3;    // If model called a tool
  string error = 4;
}

message ToolCall {
  string name = 1;
  string arguments_json = 2;
}

message CloseConversationRequest {
  string conversation_id = 1;
}

message CloseConversationResponse {
  bool success = 1;
}

message ShutdownRequest {}

message ShutdownResponse {
  bool success = 1;
}
```

#### 1.4 Server Implementation

```kotlin
// src/main/kotlin/dev/flutterberlin/litertlm/Server.kt
package dev.flutterberlin.litertlm

import io.grpc.ServerBuilder
import java.util.concurrent.TimeUnit

fun main(args: Array<String>) {
    val port = args.getOrElse(0) { "50051" }.toInt()

    val server = ServerBuilder
        .forPort(port)
        .addService(LiteRtLmServiceImpl())
        .build()

    server.start()
    println("LiteRT-LM Server started on port $port")

    Runtime.getRuntime().addShutdownHook(Thread {
        server.shutdown()
        server.awaitTermination(30, TimeUnit.SECONDS)
    })

    server.awaitTermination()
}
```

```kotlin
// src/main/kotlin/dev/flutterberlin/litertlm/LiteRtLmServiceImpl.kt
package dev.flutterberlin.litertlm

import com.google.ai.edge.litertlm.*
import dev.flutterberlin.litertlm.proto.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.ConcurrentHashMap

class LiteRtLmServiceImpl : LiteRtLmServiceGrpcKt.LiteRtLmServiceCoroutineImplBase() {

    private var engine: Engine? = null
    private val conversations = ConcurrentHashMap<String, Conversation>()
    private var conversationCounter = 0

    override suspend fun initialize(request: InitializeRequest): InitializeResponse {
        return try {
            val backend = when (request.backend) {
                "gpu" -> Backend.GPU
                else -> Backend.CPU
            }

            val config = EngineConfig(
                modelPath = request.modelPath,
                backend = backend,
                visionBackend = if (request.enableVision) Backend.GPU else null,
                audioBackend = if (request.enableAudio) Backend.CPU else null,
                maxNumTokens = request.maxTokens,
            )

            engine = Engine(config)
            engine!!.initialize()

            InitializeResponse.newBuilder()
                .setSuccess(true)
                .build()
        } catch (e: Exception) {
            InitializeResponse.newBuilder()
                .setSuccess(false)
                .setError(e.message ?: "Unknown error")
                .build()
        }
    }

    override suspend fun createConversation(request: CreateConversationRequest): CreateConversationResponse {
        val engine = this.engine ?: return CreateConversationResponse.newBuilder()
            .setError("Engine not initialized")
            .build()

        return try {
            val samplerConfig = SamplerConfig(
                topK = request.samplerConfig.topK,
                topP = request.samplerConfig.topP.toDouble(),
                temperature = request.samplerConfig.temperature.toDouble(),
            )

            val systemMessage = if (request.systemMessage.isNotEmpty()) {
                Message.of(request.systemMessage)
            } else null

            // TODO: Parse tools from request

            if (request.enableConstrainedDecoding) {
                ExperimentalFlags.enableConversationConstrainedDecoding = true
            }

            val conversation = engine.createConversation(
                ConversationConfig(
                    samplerConfig = samplerConfig,
                    systemMessage = systemMessage,
                )
            )

            ExperimentalFlags.enableConversationConstrainedDecoding = false

            val id = "conv_${++conversationCounter}"
            conversations[id] = conversation

            CreateConversationResponse.newBuilder()
                .setConversationId(id)
                .build()
        } catch (e: Exception) {
            CreateConversationResponse.newBuilder()
                .setError(e.message ?: "Unknown error")
                .build()
        }
    }

    override fun chat(request: ChatRequest): Flow<ChatResponse> = flow {
        val conversation = conversations[request.conversationId]
            ?: throw IllegalArgumentException("Conversation not found")

        val contents = mutableListOf<Content>()

        if (request.image.size() > 0) {
            contents.add(Content.ImageBytes(request.image.toByteArray()))
        }
        if (request.audio.size() > 0) {
            contents.add(Content.AudioBytes(request.audio.toByteArray()))
        }
        if (request.text.isNotEmpty()) {
            contents.add(Content.Text(request.text))
        }

        val message = Message.of(contents)

        // Use callback-based API and convert to Flow
        val channel = kotlinx.coroutines.channels.Channel<ChatResponse>()

        conversation.sendMessageAsync(message, object : MessageCallback {
            override fun onMessage(message: Message) {
                channel.trySend(
                    ChatResponse.newBuilder()
                        .setText(message.toString())
                        .setDone(false)
                        .build()
                )
            }

            override fun onDone() {
                channel.trySend(
                    ChatResponse.newBuilder()
                        .setDone(true)
                        .build()
                )
                channel.close()
            }

            override fun onError(throwable: Throwable) {
                channel.trySend(
                    ChatResponse.newBuilder()
                        .setError(throwable.message ?: "Unknown error")
                        .setDone(true)
                        .build()
                )
                channel.close()
            }
        })

        for (response in channel) {
            emit(response)
        }
    }

    override suspend fun closeConversation(request: CloseConversationRequest): CloseConversationResponse {
        val conversation = conversations.remove(request.conversationId)
        conversation?.close()
        return CloseConversationResponse.newBuilder()
            .setSuccess(true)
            .build()
    }

    override suspend fun shutdown(request: ShutdownRequest): ShutdownResponse {
        conversations.values.forEach { it.close() }
        conversations.clear()
        engine?.close()
        engine = null
        return ShutdownResponse.newBuilder()
            .setSuccess(true)
            .build()
    }
}
```

---

### Фаза 2: Сборка Native Libraries (1-2 дня)

**Цель**: Получить native библиотеки LiteRT-LM для каждой платформы.

#### 2.1 Скачать prebuilt (если доступны)

```bash
# Проверить releases
gh release download v0.9.0-alpha01 \
  --repo google-ai-edge/LiteRT-LM \
  --pattern "*.dylib" --pattern "*.dll" --pattern "*.so" \
  --dir natives/
```

#### 2.2 Собрать из исходников (если нужно)

```bash
# Clone LiteRT-LM
git clone https://github.com/google-ai-edge/LiteRT-LM.git
cd LiteRT-LM

# macOS
bazel build -c opt --config=macos_arm64 //runtime:all
cp bazel-bin/runtime/*.dylib ../natives/macos/

# Linux
bazel build -c opt --config=linux_x86_64 //runtime:all
cp bazel-bin/runtime/*.so ../natives/linux/

# Windows (из Windows машины)
bazel build -c opt --config=windows_x86_64 //runtime:all
copy bazel-bin\runtime\*.dll ..\natives\windows\
```

#### 2.3 Структура natives

```
natives/
├── macos/
│   ├── libLiteRtGpuAccelerator.dylib
│   ├── libLiteRtTopKSampler.dylib
│   └── libLiteRt.dylib
├── windows/
│   ├── LiteRtGpuAccelerator.dll
│   ├── LiteRtTopKSampler.dll
│   ├── LiteRt.dll
│   ├── dxil.dll
│   └── dxcompiler.dll
└── linux/
    ├── libLiteRtGpuAccelerator.so
    ├── libLiteRtTopKSampler.so
    └── libLiteRt.so
```

---

### Фаза 3: Dart Client (2-3 дня)

**Цель**: Создать Dart wrapper для gRPC клиента.

#### 3.1 Структура

```
lib/
├── desktop/
│   ├── litertlm_desktop.dart          # Main implementation
│   ├── litertlm_server_manager.dart   # Server process management
│   ├── litertlm_grpc_client.dart      # gRPC client
│   └── generated/                      # protoc generated files
│       ├── litertlm.pb.dart
│       ├── litertlm.pbenum.dart
│       ├── litertlm.pbgrpc.dart
│       └── litertlm.pbjson.dart
└── flutter_gemma_interface.dart        # Shared interface
```

#### 3.2 Server Manager

```dart
// lib/desktop/litertlm_server_manager.dart
import 'dart:io';
import 'package:path/path.dart' as path;

class LiteRtLmServerManager {
  Process? _serverProcess;
  final int port;

  LiteRtLmServerManager({this.port = 50051});

  Future<void> start() async {
    if (_serverProcess != null) return;

    final javaPath = await _findJava();
    final jarPath = _getJarPath();
    final nativesPath = _getNativesPath();

    _serverProcess = await Process.start(
      javaPath,
      [
        '-Djava.library.path=$nativesPath',
        '-jar', jarPath,
        port.toString(),
      ],
      environment: {
        if (Platform.isLinux) 'LD_LIBRARY_PATH': nativesPath,
        if (Platform.isMacOS) 'DYLD_LIBRARY_PATH': nativesPath,
      },
    );

    // Wait for server to start
    await Future.delayed(const Duration(seconds: 2));

    // Check if process is still running
    if (_serverProcess?.exitCode != null) {
      throw Exception('Server failed to start');
    }

    // Log server output
    _serverProcess!.stdout.transform(utf8.decoder).listen((line) {
      print('[LiteRT-LM Server] $line');
    });
    _serverProcess!.stderr.transform(utf8.decoder).listen((line) {
      print('[LiteRT-LM Server ERROR] $line');
    });
  }

  Future<void> stop() async {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  String _getNativesPath() {
    final executableDir = path.dirname(Platform.resolvedExecutable);

    if (Platform.isMacOS) {
      return path.join(executableDir, '..', 'Frameworks', 'litertlm', 'macos');
    } else if (Platform.isWindows) {
      return path.join(executableDir, 'litertlm', 'windows');
    } else if (Platform.isLinux) {
      return path.join(executableDir, 'lib', 'litertlm', 'linux');
    }
    throw UnsupportedError('Unsupported platform');
  }

  String _getJarPath() {
    final executableDir = path.dirname(Platform.resolvedExecutable);

    if (Platform.isMacOS) {
      return path.join(executableDir, '..', 'Resources', 'litertlm-server.jar');
    } else if (Platform.isWindows) {
      return path.join(executableDir, 'data', 'litertlm-server.jar');
    } else if (Platform.isLinux) {
      return path.join(executableDir, 'data', 'litertlm-server.jar');
    }
    throw UnsupportedError('Unsupported platform');
  }

  Future<String> _findJava() async {
    // Try JAVA_HOME first
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null) {
      final javaPath = path.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java');
      if (await File(javaPath).exists()) {
        return javaPath;
      }
    }

    // Try system PATH
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      ['java'],
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim().split('\n').first;
    }

    // Try bundled JRE
    final bundledJre = _getBundledJrePath();
    if (await File(bundledJre).exists()) {
      return bundledJre;
    }

    throw Exception('Java not found. Please install Java 17+ or set JAVA_HOME.');
  }

  String _getBundledJrePath() {
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final javaExe = Platform.isWindows ? 'java.exe' : 'java';

    if (Platform.isMacOS) {
      return path.join(executableDir, '..', 'Frameworks', 'jre', 'bin', javaExe);
    } else if (Platform.isWindows) {
      return path.join(executableDir, 'jre', 'bin', javaExe);
    } else {
      return path.join(executableDir, 'lib', 'jre', 'bin', javaExe);
    }
  }
}
```

#### 3.3 Desktop Implementation

```dart
// lib/desktop/litertlm_desktop.dart
import 'package:grpc/grpc.dart';
import 'generated/litertlm.pbgrpc.dart';
import 'litertlm_server_manager.dart';

class LiteRtLmDesktop implements FlutterGemmaInterface {
  final LiteRtLmServerManager _serverManager;
  late final ClientChannel _channel;
  late final LiteRtLmServiceClient _client;
  String? _conversationId;

  LiteRtLmDesktop({int port = 50051})
    : _serverManager = LiteRtLmServerManager(port: port);

  @override
  Future<void> initialize({
    required String modelPath,
    PreferredBackend preferredBackend = PreferredBackend.gpu,
    int maxTokens = 2048,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    // Start server process
    await _serverManager.start();

    // Connect gRPC client
    _channel = ClientChannel(
      'localhost',
      port: _serverManager.port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    _client = LiteRtLmServiceClient(_channel);

    // Initialize engine
    final response = await _client.initialize(InitializeRequest(
      modelPath: modelPath,
      backend: preferredBackend == PreferredBackend.gpu ? 'gpu' : 'cpu',
      maxTokens: maxTokens,
      enableVision: supportImage,
      enableAudio: supportAudio,
    ));

    if (!response.success) {
      throw Exception('Failed to initialize: ${response.error}');
    }
  }

  @override
  Future<void> createConversation({
    String? systemMessage,
    List<ToolDefinition>? tools,
    SamplerConfig? samplerConfig,
    bool enableConstrainedDecoding = false,
  }) async {
    final response = await _client.createConversation(CreateConversationRequest(
      systemMessage: systemMessage ?? '',
      samplerConfig: samplerConfig != null
        ? Proto.SamplerConfig(
            topK: samplerConfig.topK,
            topP: samplerConfig.topP,
            temperature: samplerConfig.temperature,
          )
        : null,
      enableConstrainedDecoding: enableConstrainedDecoding,
    ));

    if (response.error.isNotEmpty) {
      throw Exception('Failed to create conversation: ${response.error}');
    }

    _conversationId = response.conversationId;
  }

  @override
  Stream<String> chat(String prompt, {Uint8List? image, Uint8List? audio}) async* {
    if (_conversationId == null) {
      throw StateError('Conversation not created');
    }

    final responseStream = _client.chat(ChatRequest(
      conversationId: _conversationId!,
      text: prompt,
      image: image ?? [],
      audio: audio ?? [],
    ));

    await for (final response in responseStream) {
      if (response.error.isNotEmpty) {
        throw Exception(response.error);
      }
      if (response.text.isNotEmpty) {
        yield response.text;
      }
      if (response.done) {
        break;
      }
    }
  }

  @override
  Future<void> close() async {
    if (_conversationId != null) {
      await _client.closeConversation(
        CloseConversationRequest(conversationId: _conversationId!),
      );
    }
    await _client.shutdown(ShutdownRequest());
    await _channel.shutdown();
    await _serverManager.stop();
  }
}
```

---

### Фаза 4: Bundling & Distribution (2-3 дня)

**Цель**: Настроить сборку и упаковку для каждой платформы.

#### 4.1 macOS

```ruby
# macos/Podfile
platform :osx, '12.0'

target 'Runner' do
  use_frameworks!

  # Copy native libraries
  script_phase :name => 'Copy LiteRT-LM natives',
    :script => 'cp -R "${SRCROOT}/../litertlm-server/natives/macos/" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/litertlm/"',
    :execution_position => :after_compile
end
```

```yaml
# pubspec.yaml (assets)
flutter:
  assets:
    - assets/litertlm-server.jar
```

#### 4.2 Windows

```cmake
# windows/CMakeLists.txt
# Copy native libraries to output
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../litertlm-server/natives/windows/"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/litertlm/windows")

# Copy JAR
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../litertlm-server/litertlm-server.jar"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}")
```

#### 4.3 Linux

```cmake
# linux/CMakeLists.txt
# Copy native libraries
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../litertlm-server/natives/linux/"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/litertlm/linux")

# Copy JAR
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../litertlm-server/litertlm-server.jar"
        DESTINATION "${INSTALL_BUNDLE_DATA_DIR}")
```

---

### Фаза 5: Интеграция с flutter_gemma (1-2 дня)

**Цель**: Интегрировать desktop implementation в существующую архитектуру.

#### 5.1 Platform detection

```dart
// lib/flutter_gemma.dart
import 'dart:io';

FlutterGemmaInterface createPlatformInterface() {
  if (kIsWeb) {
    return FlutterGemmaWeb();
  } else if (Platform.isAndroid || Platform.isIOS) {
    return FlutterGemmaMobile();
  } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return LiteRtLmDesktop();
  }
  throw UnsupportedError('Unsupported platform');
}
```

#### 5.2 Feature matrix

```dart
// lib/core/platform_capabilities.dart
class PlatformCapabilities {
  static bool get supportsLitertlm {
    if (kIsWeb) return true;  // WASM runtime
    if (Platform.isAndroid) return true;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return true;
    return false;  // iOS - coming soon
  }

  static bool get supportsTask {
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  static bool get supportsNpu {
    return Platform.isAndroid;  // Qualcomm/MediaTek
  }
}
```

---

## Timeline

| Фаза | Задачи | Время |
|------|--------|-------|
| **1. Kotlin Server** | gRPC server, LiteRT-LM integration | 2-3 дня |
| **2. Native Libraries** | Build/download for all platforms | 1-2 дня |
| **3. Dart Client** | gRPC client, server manager | 2-3 дня |
| **4. Bundling** | macOS, Windows, Linux packaging | 2-3 дня |
| **5. Integration** | flutter_gemma integration | 1-2 дня |
| **Total** | | **8-13 дней** |

---

## Зависимости

### Runtime
- Java 17+ (bundled или системный)
- Native libraries (bundled)

### Build
- Kotlin 1.9+
- Gradle 8+
- protoc 3.25+
- Bazel 7.6+ (для сборки natives)

---

## Риски и митигации

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Native libs не собираются | Средняя | Использовать prebuilt из releases |
| JVM overhead большой | Низкая | GraalVM Native Image как fallback |
| gRPC latency | Низкая | Unix sockets вместо TCP |
| GPU не работает на платформе | Средняя | Fallback на CPU |

---

---

### Фаза 6: Auto-download для production (TODO)

**Цель**: Автоматическая загрузка JAR и native libraries при первом запуске, чтобы разработчикам не нужно было вручную собирать сервер.

#### 6.1 Что нужно сделать

1. **Публикация артефактов на GitHub Releases**:
   - `litertlm-server-{version}.jar` — fat JAR сервера
   - `litertlm-natives-macos-arm64.tar.gz`
   - `litertlm-natives-macos-x64.tar.gz`
   - `litertlm-natives-windows-x64.zip`
   - `litertlm-natives-linux-x64.tar.gz`

2. **Auto-download в ServerProcessManager**:
   ```dart
   Future<void> _ensureArtifactsDownloaded() async {
     final jarPath = await _getJarPath();
     if (!await File(jarPath).exists()) {
       debugPrint('[ServerProcessManager] Downloading server JAR...');
       await _downloadFile(
         'https://github.com/user/repo/releases/download/v1.0.0/litertlm-server.jar',
         jarPath,
       );
     }

     final nativesPath = await _getNativesPath();
     if (!await Directory(nativesPath).exists()) {
       debugPrint('[ServerProcessManager] Downloading native libraries...');
       await _downloadAndExtract(
         _getNativesUrl(),
         nativesPath,
       );
     }
   }
   ```

3. **Версионирование**:
   - Хранить версию в shared_preferences
   - Проверять при старте, есть ли новая версия
   - Автоматически обновлять при необходимости

4. **Опциональный bundled JRE**:
   - Для macOS: включить в .app bundle
   - Для Windows: опциональный installer с JRE
   - Для Linux: документация по установке

#### 6.2 Преимущества

- Разработчику достаточно: `flutter pub add flutter_gemma` → `flutter run -d macos`
- Не нужно устанавливать Java/Gradle для использования плагина
- Автоматические обновления native библиотек

#### 6.3 Оценка времени

| Задача | Время |
|--------|-------|
| CI/CD для публикации артефактов | 1 день |
| Auto-download логика | 1-2 дня |
| Версионирование и обновления | 1 день |
| Тестирование на всех платформах | 1-2 дня |
| **Итого** | **4-6 дней** |

---

## Альтернативы (если не сработает)

1. **llama.cpp** — C++ с готовыми FFI bindings
2. **ONNX Runtime** — кросс-платформенный, есть C API
3. **Ждать C API** от Google для LiteRT-LM

---

## Источники

- [LiteRT-LM GitHub](https://github.com/google-ai-edge/LiteRT-LM)
- [LiteRT-LM Kotlin README](https://github.com/google-ai-edge/LiteRT-LM/blob/main/kotlin/README.md)
- [gRPC Kotlin](https://grpc.io/docs/languages/kotlin/)
- [Flutter Desktop](https://docs.flutter.dev/desktop)
