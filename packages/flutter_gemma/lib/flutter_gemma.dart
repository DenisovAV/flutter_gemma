export 'flutter_gemma_interface.dart';
export 'model_file_manager_interface.dart';

// Vector store filter DSL — passed to searchSimilar to constrain results
// by payload. Honored on every native platform (qdrant-edge); silently
// ignored on Web.
export 'core/services/vector_store_filter.dart';
export 'core/services/vector_store_repository.dart'; // VectorStoreRepository + VectorStoreException for opt-in RAG packages
export 'core/domain/platform_types.dart'; // PreferredBackend + RAG value types
export 'core/message.dart';
export 'core/model.dart'; // Export ModelType and other model-related classes
export 'core/model_response.dart';
export 'core/function_call_parser.dart';
export 'core/tool.dart';
export 'core/utils/gemma_log.dart' show GemmaLogLevel;
export 'core/chat.dart';
export 'core/model_management/cancel_token.dart';

// Export image processing utilities to prevent AI image corruption
export 'core/image_processor.dart';
export 'core/image_tokenizer.dart' hide ModelType;
export 'core/vision_encoder_validator.dart';
export 'core/image_error_handler.dart';
export 'core/multimodal_image_handler.dart';

// Export Modern API
export 'core/api/flutter_gemma.dart';
export 'core/api/inference_installation_builder.dart';
export 'core/api/embedding_installation_builder.dart';

// Export Web-specific types
export 'core/domain/web_storage_mode.dart';

// Export Model Specs (needed for advanced use cases). These dart:io-free value
// types live in their own library so the public API doesn't pull the mobile
// implementation (and its dart:io) into the web/wasm graph.
export 'core/model_management/model_specs.dart'
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
