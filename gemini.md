
# Project Gemini: Flutter Gemma Plugin Knowledge Base

## 1. Project Overview

This project, `flutter_gemma`, is a Flutter plugin designed to integrate Google's Gemma AI models into Flutter applications. It provides a unified interface in Dart for developers to interact with Gemma models, while handling the platform-specific implementations for iOS, Android, and Web. The plugin manages the complexities of model loading, inference, and communication between the Flutter front-end and the native back-end.

## 2. Core Technologies

- **Flutter & Dart:** The primary framework for the plugin's cross-platform API and the example application.
- **Pigeon:** A code generation tool used to create a type-safe communication channel between the Dart code and the native iOS/Android platforms. This avoids the need for manual method channel mapping.
- **Swift:** Used for the native iOS implementation of the Gemma inference engine.
- **Kotlin:** Used for the native Android implementation.
- **Web:** A web implementation is also provided, likely using a JavaScript-based inference library.

## 3. Architecture

The plugin follows a federated plugin architecture. A central interface package, `flutter_gemma`, defines the API, and platform-specific packages provide the concrete implementations.

- **Interface (`flutter_gemma`):** Defines the abstract classes and methods that the app-facing code will use.
- **Platform Implementations (`flutter_gemma_mobile`, `flutter_gemma_web`):**
    - **Mobile (iOS & Android):** Uses Pigeon to communicate with native code. The native code is responsible for running the Gemma model inference.
    - **Web:** Uses a web-compatible library to run inference directly in the browser.
- **Pigeon Integration:** The `pigeon.dart` file defines the interface (API) that will be implemented on the native side (Swift/Kotlin) and called from the Dart side. Running the Pigeon generator creates the `pigeon.g.dart` (Dart stubs) and `PigeonInterface.g.swift` (Swift stubs) files, ensuring type safety across the platform boundary.

## 4. Key File Structure

- `/lib`: Contains all the Dart code for the plugin.
  - `flutter_gemma.dart`: The main entry point for the plugin's Dart API. It exposes the high-level classes and methods for developers.
  - `pigeon.g.dart`: The auto-generated Dart part of the Pigeon communication interface.
  - `/core`: Contains the core data models and business logic (e.g., `Message`, `Chat`, `Tool`) that are platform-agnostic.
  - `/mobile`: Contains the Dart implementation for the mobile platforms (iOS/Android), which calls into the native side via the generated Pigeon stubs.
  - `/web`: Contains the Dart implementation for the web platform.
- `/ios`: Contains the native iOS implementation.
  - `Classes/`: Swift files that implement the native functionality.
    - `FlutterGemmaPlugin.swift`: The main entry point for the iOS plugin.
    - `InferenceModel.swift`: Handles the logic for loading the Gemma model and running inference.
    - `PigeonInterface.g.swift`: The auto-generated Swift protocol and stubs from Pigeon.
  - `flutter_gemma.podspec`: The CocoaPods specification for the iOS part of the plugin.
- `/android`: Contains the native Android implementation (Kotlin).
  - `src/main/kotlin/`: Kotlin source code for the Android implementation.
- `/example`: A complete Flutter application demonstrating how to use the `flutter_gemma` plugin.
  - `lib/main.dart`: The entry point of the example app.
  - `lib/chat_screen.dart`: The main UI for the chat interface, showcasing the plugin in action.
- `pigeon.dart`: The Pigeon definition file. This is the single source of truth for the Dart-to-native API contract.
- `pubspec.yaml`: The Dart package manager configuration file. It defines the plugin's name, description, dependencies, and platform-specific plugin configurations.
- `claude.md`: An existing knowledge base file, used as a reference for creating this document.
- `gemini.md`: This file. The primary knowledge base for the project.

## 5. Key Concepts

- **Inference:** The process of running the Gemma model to get a response. This is handled by the native code on mobile and a web library on the web.
- **Model Management:** The plugin needs to handle the downloading, storage, and loading of the Gemma model files. The `path_provider` dependency suggests that it stores models in the application's documents directory.
- **Chat Session:** The plugin manages a chat session, keeping track of the conversation history to provide context for the Gemma model.

