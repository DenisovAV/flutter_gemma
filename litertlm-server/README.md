[🇬🇧 English](./readme.en.md) | [🇷🇺 Русский](./README.md)

# LiteRT-LM gRPC Server

gRPC сервер для LiteRT-LM, обеспечивающий интеграцию с Flutter Desktop.

## Требования

- Java 17+
- Gradle 8.5+ (или используйте wrapper после инициализации)

## Сборка

```bash
# Инициализация Gradle wrapper (один раз)
gradle wrapper --gradle-version 8.5

# Сборка
./gradlew build

# Создание fat JAR
./gradlew fatJar
```

## Запуск

```bash
# Запуск на порту по умолчанию (50051)
java -jar build/libs/litertlm-server-0.1.0-all.jar

# Запуск на кастомном порту
java -jar build/libs/litertlm-server-0.1.0-all.jar 50052
```

## gRPC API

### Initialize
Инициализация движка с моделью.

```protobuf
rpc Initialize(InitializeRequest) returns (InitializeResponse);
```

### CreateConversation
Создание нового диалога.

```protobuf
rpc CreateConversation(CreateConversationRequest) returns (CreateConversationResponse);
```

### Chat
Отправка сообщения со стримингом ответа.

```protobuf
rpc Chat(ChatRequest) returns (stream ChatResponse);
```

### ChatWithImage
Мультимодальный запрос (текст + изображение).

```protobuf
rpc ChatWithImage(ChatWithImageRequest) returns (stream ChatResponse);
```

## Тестирование с grpcurl

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

Для работы LiteRT-LM требуются native библиотеки:

- **macOS**: `libLiteRtMetalAccelerator.dylib`
- **Windows**: `LiteRtGpuAccelerator.dll`
- **Linux**: `libLiteRtGpuAccelerator.so`

Скачать из [LiteRT-LM releases](https://github.com/google-ai-edge/LiteRT-LM/releases).

Положить в `natives/<platform>/` или указать через `-Djava.library.path`.

## Скрипты

### Сборка сервера
```bash
./scripts/build.sh
```

### Загрузка native библиотек
```bash
./scripts/setup_natives.sh          # авто-определение платформы
./scripts/setup_natives.sh macos    # явное указание
```

### Бандлинг для macOS Flutter app
```bash
./scripts/bundle_macos.sh /path/to/your/flutter_app
```

## macOS Bundling

Для включения LiteRT-LM сервера в ваше macOS приложение:

### 1. Подготовка
```bash
cd litertlm-server

# Сборка JAR
./scripts/build.sh

# Загрузка native библиотек
./scripts/setup_natives.sh macos
```

### 2. Бандлинг в Flutter app
```bash
./scripts/bundle_macos.sh /path/to/your/flutter_app
```

### 3. Настройка Xcode
1. Откройте `macos/Runner.xcworkspace`
2. Выберите target Runner
3. Build Phases → + → New Run Script Phase
4. Добавьте: `"${PROJECT_DIR}/Runner/copy_litertlm.sh"`

### 4. Запуск
```bash
flutter run -d macos
```

## Структура файлов в app bundle

```
MyApp.app/Contents/
├── Resources/
│   └── litertlm-server.jar      # gRPC сервер
├── Frameworks/
│   └── litertlm/
│       └── macos/
│           └── libLiteRtMetalAccelerator.dylib
└── MacOS/
    └── MyApp                    # Flutter executable
```
