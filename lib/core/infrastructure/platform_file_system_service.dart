import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_gemma/core/services/file_system_service.dart';

/// Platform-specific file system implementation using dart:io
///
/// Features:
/// - Uses path_provider for platform directories
/// - Supports Android and iOS
/// - Automatic parent directory creation
/// - External file registration tracking
class PlatformFileSystemService implements FileSystemService {
  // Cache for app documents directory
  Directory? _documentsDirectory;

  @override
  Future<void> writeFile(String filePath, Uint8List data) async {
    final file = File(filePath);

    // Create parent directories if they don't exist
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    await file.writeAsBytes(data);
  }

  @override
  Future<Uint8List> readFile(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    return await file.readAsBytes();
  }

  @override
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  @override
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      return 0;
    }

    final stat = await file.stat();
    return stat.size;
  }

  @override
  Future<String> getTargetPath(String filename) async {
    final dir = await _getDocumentsDirectory();
    return path.join(dir.path, filename);
  }

  @override
  Future<String> getBundledResourcePath(String resourceName) async {
    // Web doesn't support bundled resources via this service
    if (kIsWeb) {
      throw UnsupportedError('Bundled resources not supported on web platform');
    }

    // Platform-specific bundled resource handling
    if (Platform.isAndroid) {
      // Android: Copy from native assets to filesDir (MediaPipe can't read from APK directly)
      final dir = await _getDocumentsDirectory();
      final destPath = path.join(dir.path, resourceName);
      final destFile = File(destPath);

      // Check if already copied
      if (await destFile.exists()) {
        return destPath;
      }

      // Copy from native assets via platform channel
      const platform = MethodChannel('flutter_gemma_bundled');
      final result = await platform.invokeMethod<String>(
        'copyAssetToFile',
        {
          'assetPath': 'models/$resourceName',
          'destPath': destPath,
        },
      );

      if (result == null || result != 'success') {
        throw Exception('Failed to copy asset from Android assets');
      }

      return destPath;
    } else if (Platform.isIOS) {
      // On iOS, MediaPipe CAN read directly from Bundle (after iOS native fix)
      // Simply get the bundle path and return it - no copying needed!
      const platform = MethodChannel('flutter_gemma_bundled');
      final bundlePath = await platform.invokeMethod<String>(
        'getBundledResourcePath',
        {'resourceName': resourceName},
      );

      if (bundlePath == null) {
        throw Exception('Bundled resource not found: $resourceName');
      }

      return bundlePath;
    } else {
      throw UnsupportedError('Bundled resources not supported on ${Platform.operatingSystem}');
    }
  }

  @override
  Future<void> registerExternalFile(String filename, String externalPath) async {
    // External file registration is handled by ProtectedFilesRegistry
    // This method is a no-op here since file system doesn't track registrations
    // The actual tracking is done in ProtectedFilesRegistry.registerExternalPath()
  }

  /// Gets the model storage directory with caching.
  ///
  /// On desktop platforms, uses platform-specific local app data directories
  /// that are NOT synced to cloud services (OneDrive, iCloud, Dropbox).
  /// This is critical because native code (LiteRT-LM JNI) cannot reliably
  /// access files in cloud-synced folders.
  ///
  /// Storage locations:
  /// - Windows: %LOCALAPPDATA%\flutter_gemma (truly local, never synced)
  /// - macOS: ~/Library/Application Support/flutter_gemma
  /// - Linux: ~/.local/share/flutter_gemma
  /// - Android/iOS: App documents directory (standard behavior)
  Future<Directory> _getDocumentsDirectory() async {
    // Web doesn't support local file system
    if (kIsWeb) {
      throw UnsupportedError('Local file system not supported on web platform');
    }

    if (_documentsDirectory != null) {
      return _documentsDirectory!;
    }

    if (Platform.isWindows) {
      // Use LOCALAPPDATA on Windows - truly local and never synced
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        _documentsDirectory = Directory(path.join(localAppData, 'OroForge', 'models'));
      } else {
        _documentsDirectory = await getApplicationSupportDirectory();
      }
    } else if (Platform.isMacOS) {
      // Use Application Support on macOS - not synced by default
      final home = Platform.environment['HOME'];
      if (home != null) {
        _documentsDirectory = Directory(path.join(home, 'Library', 'Application Support', 'OroForge', 'models'));
      } else {
        _documentsDirectory = await getApplicationSupportDirectory();
      }
    } else if (Platform.isLinux) {
      // Use XDG data directory on Linux
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
      if (xdgDataHome != null) {
        _documentsDirectory = Directory(path.join(xdgDataHome, 'OroForge', 'models'));
      } else {
        final home = Platform.environment['HOME'];
        if (home != null) {
          _documentsDirectory = Directory(path.join(home, '.local', 'share', 'OroForge', 'models'));
        } else {
          _documentsDirectory = await getApplicationSupportDirectory();
        }
      }
    } else {
      // Mobile platforms use standard documents directory
      _documentsDirectory = await getApplicationDocumentsDirectory();
    }

    return _documentsDirectory!;
  }
}
