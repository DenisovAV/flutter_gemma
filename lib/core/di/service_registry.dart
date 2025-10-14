import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/asset_loader.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';
import 'package:flutter_gemma/core/services/protected_files_registry.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/handlers/network_source_handler.dart';
import 'package:flutter_gemma/core/handlers/asset_source_handler.dart';
import 'package:flutter_gemma/core/handlers/web_asset_source_handler.dart';
import 'package:flutter_gemma/core/handlers/bundled_source_handler.dart';
import 'package:flutter_gemma/core/handlers/file_source_handler.dart';
import 'package:flutter_gemma/core/handlers/web_bundled_source_handler.dart';
import 'package:flutter_gemma/core/handlers/web_file_source_handler.dart';
import 'package:flutter_gemma/core/handlers/source_handler_registry.dart';
import 'package:flutter_gemma/core/infrastructure/platform_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/flutter_asset_loader.dart';
import 'package:flutter_gemma/core/infrastructure/shared_preferences_model_repository.dart';
import 'platform/mobile_service_factory.dart'
  if (dart.library.js_interop) 'platform/web_service_factory.dart' as platform;
import 'package:flutter_gemma/core/infrastructure/shared_preferences_protected_registry.dart';

/// Dependency Injection Container for managing service lifecycle
///
/// Features:
/// - Singleton pattern - one instance per application
/// - Platform-aware service selection (web vs mobile)
/// - Lazy initialization of services
/// - Constructor injection for testability
/// - Clear separation of concerns
///
/// Platform Support:
/// - Mobile: Uses dart:io-based services (PlatformFileSystemService, BackgroundDownloaderService)
/// - Web: Uses URL-based services (WebFileSystemService, WebDownloadService)
///
/// Requirements:
/// - Mobile platforms require Flutter bindings to be initialized before ServiceRegistry
///   (BackgroundDownloaderService uses path_provider which requires bindings)
/// - Call `WidgetsFlutterBinding.ensureInitialized()` in main() before using ServiceRegistry
///
/// Usage:
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized(); // Required for mobile
///   ServiceRegistry.initialize();
///   runApp(MyApp());
/// }
///
/// // Later in your code:
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
  late final SourceHandler _assetHandler;
  late final SourceHandler _bundledHandler;  // Changed from BundledSourceHandler
  late final SourceHandler _fileHandler;      // Changed from FileSourceHandler

  // Handler registry
  late final SourceHandlerRegistry _sourceHandlerRegistry;

  // Optional configuration
  final String? huggingFaceToken;
  final int maxDownloadRetries;

  /// Creates the default FileSystemService based on platform
  ///
  /// - Web: WebFileSystemService (URL-based storage)
  /// - Mobile: PlatformFileSystemService (dart:io file system)
  static FileSystemService _createDefaultFileSystemService() {
    if (kIsWeb) {
      return WebFileSystemService();
    } else {
      return PlatformFileSystemService();
    }
  }

  /// Creates the default DownloadService based on platform
  ///
  /// - Web: WebDownloadService (URL registration + authenticated fetch)
  /// - Mobile: BackgroundDownloaderService (actual file downloads)
  ///
  /// Note: Web version requires WebFileSystemService (validated in constructor)
  static DownloadService _createDefaultDownloadService(
    FileSystemService fileSystem,
  ) {
    if (kIsWeb) {
      // Web requires WebFileSystemService - validated in constructor
      final webFs = fileSystem as WebFileSystemService;
      return platform.createDownloadService(webFs);
    } else {
      // Mobile doesn't need file system parameter
      return platform.createDownloadService();
    }
  }

  /// Creates the appropriate AssetSourceHandler based on platform
  ///
  /// - Web: WebAssetSourceHandler (URL registration only)
  /// - Mobile: AssetSourceHandler (file copying with LargeFileHandler)
  static SourceHandler _createAssetSourceHandler(
    FileSystemService fileSystem,
    AssetLoader assetLoader,
    ModelRepository repository,
  ) {
    if (kIsWeb) {
      // Web: Use WebAssetSourceHandler
      // Type-safe cast (validated in constructor)
      final webFs = fileSystem as WebFileSystemService;
      return WebAssetSourceHandler(
        fileSystem: webFs,
        repository: repository,
      );
    } else {
      // Mobile: Use AssetSourceHandler with file copying
      return AssetSourceHandler(
        assetLoader: assetLoader,
        fileSystem: fileSystem,
        repository: repository,
      );
    }
  }

  /// Creates the appropriate BundledSourceHandler based on platform
  ///
  /// - Web: WebBundledSourceHandler (URL registration only)
  /// - Mobile: BundledSourceHandler (native bundle path)
  static SourceHandler _createBundledSourceHandler(
    FileSystemService fileSystem,
    ModelRepository repository,
  ) {
    if (kIsWeb) {
      // Web: Use WebBundledSourceHandler
      // Type-safe cast (validated in constructor)
      final webFs = fileSystem as WebFileSystemService;
      return WebBundledSourceHandler(
        fileSystem: webFs,
        repository: repository,
      );
    } else {
      // Mobile: Use BundledSourceHandler
      return BundledSourceHandler(
        fileSystem: fileSystem,
        repository: repository,
      );
    }
  }

  /// Creates the appropriate FileSourceHandler based on platform
  ///
  /// - Web: WebFileSourceHandler (URL validation and registration)
  /// - Mobile: FileSourceHandler (external file registration)
  static SourceHandler _createFileSourceHandler(
    FileSystemService fileSystem,
    ProtectedFilesRegistry protectedFiles,
    ModelRepository repository,
  ) {
    if (kIsWeb) {
      // Web: Use WebFileSourceHandler
      // Type-safe cast (validated in constructor)
      final webFs = fileSystem as WebFileSystemService;
      return WebFileSourceHandler(
        fileSystem: webFs,
        repository: repository,
      );
    } else {
      // Mobile: Use FileSourceHandler
      return FileSourceHandler(
        fileSystem: fileSystem,
        protectedFiles: protectedFiles,
        repository: repository,
      );
    }
  }

  ServiceRegistry._({
    this.huggingFaceToken,
    this.maxDownloadRetries = 10,
    FileSystemService? fileSystemService,
    AssetLoader? assetLoader,
    DownloadService? downloadService,
    ModelRepository? modelRepository,
    ProtectedFilesRegistry? protectedFilesRegistry,
  }) {
    // Initialize infrastructure services with platform-aware factories
    _fileSystemService = fileSystemService ?? _createDefaultFileSystemService();
    _assetLoader = assetLoader ?? FlutterAssetLoader();

    // Validate web platform requirements early
    if (kIsWeb && _fileSystemService is! WebFileSystemService) {
      throw ArgumentError(
        'Web platform requires WebFileSystemService. '
        'Either provide WebFileSystemService explicitly or use platform defaults.',
      );
    }

    _downloadService = downloadService ?? _createDefaultDownloadService(
      _fileSystemService,
    );
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

    _assetHandler = _createAssetSourceHandler(
      _fileSystemService,
      _assetLoader,
      _modelRepository,
    );

    _bundledHandler = _createBundledSourceHandler(
      _fileSystemService,
      _modelRepository,
    );

    _fileHandler = _createFileSourceHandler(
      _fileSystemService,
      _protectedFilesRegistry,
      _modelRepository,
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
  /// Multiple calls to initialize() are safe - subsequent calls are ignored.
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
    // Make idempotent - skip if already initialized
    if (_instance != null) {
      debugPrint('ServiceRegistry: Already initialized, skipping re-initialization');
      return;
    }

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

  SourceHandler get assetHandler => _assetHandler;

  SourceHandler get bundledHandler => _bundledHandler;

  SourceHandler get fileHandler => _fileHandler;
}
