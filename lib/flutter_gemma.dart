export 'flutter_gemma_interface.dart';
export 'model_file_manager_interface.dart';
export 'pigeon.g.dart'; // Export generated types like PreferredBackend, ModelFileType, etc.
export 'core/message.dart';
export 'core/model.dart'; // Export ModelType and other model-related classes
export 'core/model_response.dart';
export 'core/function_call_parser.dart';
export 'core/tool.dart';
export 'core/chat.dart';
export 'core/model_management/cancel_token.dart';

// Export image processing utilities to prevent AI image corruption
export 'core/image_processor.dart';
export 'core/image_tokenizer.dart' hide ModelType;
export 'core/vision_encoder_validator.dart';
export 'core/image_error_handler.dart';
export 'core/multimodal_image_handler.dart';

// Export migration utilities (optional, user must call explicitly)
export 'core/migration/legacy_preferences_migrator.dart';

// Export Modern API
export 'core/api/flutter_gemma.dart';
export 'core/api/inference_installation_builder.dart';
export 'core/api/embedding_installation_builder.dart';

// Export Web-specific types
export 'core/domain/web_storage_mode.dart';

// Export Model Specs (needed for advanced use cases)
export 'mobile/flutter_gemma_mobile.dart'
    show
        // Model specifications
        InferenceModelSpec,
        EmbeddingModelSpec,
        ModelSpec,
        ModelFile,
        // Download progress
        DownloadProgress,
        // Storage info
        StorageStats,
        OrphanedFileInfo,
        // Model management types
        ModelManagementType,
        // Exceptions
        ModelStorageException;

// Export Desktop implementation (conditionally - only on non-web platforms)
// Note: Desktop uses MobileModelManager for file management
export 'desktop/flutter_gemma_desktop.dart'
    if (dart.library.js_interop) 'desktop/flutter_gemma_desktop_stub.dart'
    show FlutterGemmaDesktop, isDesktop;

// ModelReplacePolicy is already exported from model_file_manager_interface.dart
