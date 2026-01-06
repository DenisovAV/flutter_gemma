# LiteRT-LM gRPC Server

gRPC server for LiteRT-LM providing integration with Flutter Desktop.

## Requirements

- Java 17+
- Gradle 8.5+ (or use the wrapper after initialization)

## Build

```bash
# Initialize Gradle wrapper (one time)
gradle wrapper --gradle-version 8.5

# Build
./gradlew build

# Create fat JAR
./gradlew fatJar
```

## Run

```bash
# Run on default port (50051)
java -jar build/libs/litertlm-server-0.1.0-all.jar

# Run on a custom port
java -jar build/libs/litertlm-server-0.1.0-all.jar 50052
```

## gRPC API

### Initialize

Initialize the engine with a model.

```protobuf
rpc Initialize(InitializeRequest) returns (InitializeResponse);
```

### CreateConversation

Create a new conversation.

```protobuf
rpc CreateConversation(CreateConversationRequest) returns (CreateConversationResponse);
```

### Chat

Send a message with a streaming response.

```protobuf
rpc Chat(ChatRequest) returns (stream ChatResponse);
```

### ChatWithImage

Multimodal request (text + image).

```protobuf
rpc ChatWithImage(ChatWithImageRequest) returns (stream ChatResponse);
```

## Testing with grpcurl

```bash
# Health check
grpcurl -plaintext localhost:50051 litertlm.LiteRtLmService/HealthCheck

# Initialize
grpcurl -plaintext -d '{
  "model_path": "/path/to/model.litertlm",
  "backend": "gpu",
  "max_tokens": 2048
}' localhost:50051 litertlm.LiteRtLmService/Initialize

# Create conversation
grpcurl -plaintext -d '{
  "system_message": "You are a helpful assistant."
}' localhost:50051 litertlm.LiteRtLmService/CreateConversation

# Chat
grpcurl -plaintext -d '{
  "conversation_id": "conv_1",
  "text": "Hello!"
}' localhost:50051 litertlm.LiteRtLmService/Chat
```

## Native Libraries

Native libraries are required to run LiteRT-LM:

- macOS: `libLiteRtMetalAccelerator.dylib`
- Windows: `LiteRtGpuAccelerator.dll`
- Linux: `libLiteRtGpuAccelerator.so`

Download from [LiteRT-LM releases](https://github.com/google-ai-edge/LiteRT-LM/releases).

Place them in `natives/<platform>/` or set via `-Djava.library.path`.

## Scripts

### Build server
```bash
./scripts/build.sh
```

### Download native libraries
```bash
./scripts/setup_natives.sh          # auto-detect platform
./scripts/setup_natives.sh macos    # explicit platform
```

### Bundling for macOS Flutter app
```bash
./scripts/bundle_macos.sh /path/to/your/flutter_app
```

## macOS Bundling

To include the LiteRT-LM server in your macOS application:

### 1. Preparation
```bash
cd litertlm-server

# Build JAR
./scripts/build.sh

# Download native libraries
./scripts/setup_natives.sh macos
```

### 2. Bundling in Flutter app
```bash
./scripts/bundle_macos.sh /path/to/your/flutter_app
```

### 3. Xcode setup
1. Open `macos/Runner.xcworkspace`
2. Select the Runner target
3. Build Phases → + → New Run Script Phase
4. Add: `"${PROJECT_DIR}/Runner/copy_litertlm.sh"`

### 4. Run
```bash
flutter run -d macos
```

## Structure of files in the app bundle

```
MyApp.app/Contents/
├── Resources/
│   └── litertlm-server.jar      # gRPC server
├── Frameworks/
│   └── litertlm/
│       └── macos/
│           └── libLiteRtMetalAccelerator.dylib
└── MacOS/
    └── MyApp                    # Flutter executable
```
