import 'dart:io';
import 'dart:typed_data';
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
    // Platform-specific bundled resource handling
    if (Platform.isAndroid) {
      // On Android, bundled resources are in assets/models/
      // This path is used by native MediaPipe integration
      return 'assets/models/$resourceName';
    } else if (Platform.isIOS) {
      // On iOS, use Bundle.main path
      // The native iOS code will resolve this through Bundle.main.path(forResource:)
      // For now, we return the resource name and let native handle it
      // In a full implementation, this would call iOS platform channel
      throw UnsupportedError('iOS bundled resources require platform channel integration');
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

  /// Gets the app documents directory with caching
  Future<Directory> _getDocumentsDirectory() async {
    if (_documentsDirectory != null) {
      return _documentsDirectory!;
    }

    _documentsDirectory = await getApplicationDocumentsDirectory();
    return _documentsDirectory!;
  }
}
