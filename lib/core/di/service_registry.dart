import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/asset_loader.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';
import 'package:flutter_gemma/core/services/protected_files_registry.dart';
import 'package:flutter_gemma/core/handlers/network_source_handler.dart';
import 'package:flutter_gemma/core/handlers/asset_source_handler.dart';
import 'package:flutter_gemma/core/handlers/bundled_source_handler.dart';
import 'package:flutter_gemma/core/handlers/file_source_handler.dart';
import 'package:flutter_gemma/core/handlers/source_handler_registry.dart';
import 'package:flutter_gemma/core/infrastructure/platform_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/flutter_asset_loader.dart';
import 'package:flutter_gemma/core/infrastructure/background_downloader_service.dart';
import 'package:flutter_gemma/core/infrastructure/shared_preferences_model_repository.dart';
import 'package:flutter_gemma/core/infrastructure/shared_preferences_protected_registry.dart';

/// Dependency Injection Container for managing service lifecycle
///
/// Features:
/// - Singleton pattern - one instance per application
/// - Lazy initialization of services
/// - Constructor injection for testability
/// - Clear separation of concerns
///
/// Usage:
/// ```dart
/// final registry = ServiceRegistry.instance;
/// final handlerRegistry = registry.sourceHandlerRegistry;
/// final handler = handlerRegistry.getHandler(source);
/// await handler.install(source);
/// ```
class ServiceRegistry {
  static ServiceRegistry? _instance;

  // Infrastructure services (singletons)
  late final FileSystemService _fileSystemService;
  late final AssetLoader _assetLoader;
  late final DownloadService _downloadService;
  late final ModelRepository _modelRepository;
  late final ProtectedFilesRegistry _protectedFilesRegistry;

  // Handlers (created once with dependencies)
  late final NetworkSourceHandler _networkHandler;
  late final AssetSourceHandler _assetHandler;
  late final BundledSourceHandler _bundledHandler;
  late final FileSourceHandler _fileHandler;

  // Handler registry
  late final SourceHandlerRegistry _sourceHandlerRegistry;

  // Optional configuration
  final String? huggingFaceToken;
  final int maxDownloadRetries;

  ServiceRegistry._({
    this.huggingFaceToken,
    this.maxDownloadRetries = 10,
    FileSystemService? fileSystemService,
    AssetLoader? assetLoader,
    DownloadService? downloadService,
    ModelRepository? modelRepository,
    ProtectedFilesRegistry? protectedFilesRegistry,
  }) {
    // Initialize infrastructure services
    _fileSystemService = fileSystemService ?? PlatformFileSystemService();
    _assetLoader = assetLoader ?? FlutterAssetLoader();
    _downloadService = downloadService ?? BackgroundDownloaderService();
    _modelRepository = modelRepository ?? SharedPreferencesModelRepository();
    _protectedFilesRegistry =
        protectedFilesRegistry ?? SharedPreferencesProtectedRegistry();

    // Initialize handlers with dependencies
    _networkHandler = NetworkSourceHandler(
      downloadService: _downloadService,
      fileSystem: _fileSystemService,
      repository: _modelRepository,
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
    );

    _assetHandler = AssetSourceHandler(
      assetLoader: _assetLoader,
      fileSystem: _fileSystemService,
      repository: _modelRepository,
    );

    _bundledHandler = BundledSourceHandler(
      fileSystem: _fileSystemService,
      repository: _modelRepository,
    );

    _fileHandler = FileSourceHandler(
      fileSystem: _fileSystemService,
      protectedFiles: _protectedFilesRegistry,
      repository: _modelRepository,
    );

    // Initialize handler registry
    _sourceHandlerRegistry = SourceHandlerRegistry(
      handlers: [
        _networkHandler,
        _assetHandler,
        _bundledHandler,
        _fileHandler,
      ],
    );
  }

  /// Gets the singleton instance
  ///
  /// Automatically initializes with default settings if not already initialized.
  static ServiceRegistry get instance {
    if (_instance == null) {
      // Lazy initialization with defaults
      initialize();
    }
    return _instance!;
  }

  /// Initializes the singleton instance
  ///
  /// Call this once at app startup, before using [instance].
  ///
  /// Parameters:
  /// - [huggingFaceToken]: Optional HuggingFace API token for authenticated downloads
  /// - [maxDownloadRetries]: Maximum retry attempts for transient errors (default: 10)
  ///   Note: Auth errors (401/403/404) fail after 1 attempt regardless
  /// - Services can be overridden for testing (dependency injection)
  static void initialize({
    String? huggingFaceToken,
    int maxDownloadRetries = 10,
    FileSystemService? fileSystemService,
    AssetLoader? assetLoader,
    DownloadService? downloadService,
    ModelRepository? modelRepository,
    ProtectedFilesRegistry? protectedFilesRegistry,
  }) {
    _instance = ServiceRegistry._(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
      fileSystemService: fileSystemService,
      assetLoader: assetLoader,
      downloadService: downloadService,
      modelRepository: modelRepository,
      protectedFilesRegistry: protectedFilesRegistry,
    );
  }

  /// Resets the singleton (primarily for testing)
  static void reset() {
    _instance = null;
  }

  // Public getters for services

  SourceHandlerRegistry get sourceHandlerRegistry => _sourceHandlerRegistry;

  FileSystemService get fileSystemService => _fileSystemService;

  AssetLoader get assetLoader => _assetLoader;

  DownloadService get downloadService => _downloadService;

  ModelRepository get modelRepository => _modelRepository;

  ProtectedFilesRegistry get protectedFilesRegistry =>
      _protectedFilesRegistry;

  // Handlers (if needed directly)

  NetworkSourceHandler get networkHandler => _networkHandler;

  AssetSourceHandler get assetHandler => _assetHandler;

  BundledSourceHandler get bundledHandler => _bundledHandler;

  FileSourceHandler get fileHandler => _fileHandler;
}
