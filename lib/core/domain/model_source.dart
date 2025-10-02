import 'package:flutter/foundation.dart' show kIsWeb;

// Constants for URL schemes and validation
const _httpScheme = 'http';
const _httpsScheme = 'https';
const _assetsPrefix = 'assets/';
const _pathSeparator = '/';
const _parentDirReference = '..';

/// Sealed class representing all possible model sources
/// Provides type-safe alternative to string URLs
sealed class ModelSource {
  const ModelSource();

  /// Creates a network-based source (HTTPS/HTTP)
  factory ModelSource.network(String url) = NetworkSource;

  /// Creates an asset-based source (Flutter assets)
  factory ModelSource.asset(String path) = AssetSource;

  /// Creates a bundled resource source (native resources)
  factory ModelSource.bundled(String resourceName) = BundledSource;

  /// Creates a file-based source (external files, mobile only)
  factory ModelSource.file(String path) = FileSource;

  /// Whether this source requires downloading
  bool get requiresDownload;

  /// Whether this source supports progress tracking
  bool get supportsProgress;

  /// Whether this source supports resume after interruption
  bool get supportsResume;

  /// Validates if LoRA source is compatible with this model source
  bool validateLoraSource(ModelSource loraSource);
}

/// Network source - downloads from HTTPS/HTTP URLs
final class NetworkSource extends ModelSource {
  final String url;

  NetworkSource(this.url) {
    if (url.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || ![_httpScheme, _httpsScheme].contains(uri.scheme)) {
      throw ArgumentError('Invalid URL: $url. Must be HTTP or HTTPS.');
    }
  }

  /// Whether the connection uses HTTPS
  bool get isSecure => url.startsWith('$_httpsScheme://');

  @override
  bool get requiresDownload => true;

  @override
  bool get supportsProgress => true;

  @override
  bool get supportsResume => true;

  @override
  bool validateLoraSource(ModelSource loraSource) => loraSource is NetworkSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NetworkSource && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'NetworkSource(url: $url, secure: $isSecure)';
}

/// Asset source - copies from Flutter assets
final class AssetSource extends ModelSource {
  final String path;

  AssetSource(this.path) {
    if (path.isEmpty) {
      throw ArgumentError('Asset path cannot be empty');
    }
    if (path.contains(_parentDirReference)) {
      throw ArgumentError('Asset path cannot contain "$_parentDirReference"');
    }
    if (path.startsWith(_httpScheme)) {
      throw ArgumentError('Asset path cannot be a URL');
    }
  }

  /// Normalized path with 'assets/' prefix
  String get normalizedPath {
    String normalized = path;
    if (normalized.startsWith(_pathSeparator)) {
      normalized = normalized.substring(1);
    }
    if (!normalized.startsWith(_assetsPrefix)) {
      normalized = '$_assetsPrefix$normalized';
    }
    return normalized;
  }

  @override
  bool get requiresDownload => false;

  @override
  bool get supportsProgress => true; // Simulated

  @override
  bool get supportsResume => false;

  @override
  bool validateLoraSource(ModelSource loraSource) => loraSource is AssetSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetSource && other.normalizedPath == normalizedPath;

  @override
  int get hashCode => normalizedPath.hashCode;

  @override
  String toString() => 'AssetSource(path: $normalizedPath)';
}

/// Bundled source - native platform resources
final class BundledSource extends ModelSource {
  final String resourceName;

  BundledSource(this.resourceName) {
    if (resourceName.isEmpty) {
      throw ArgumentError('Resource name cannot be empty');
    }
    if (resourceName.contains(_pathSeparator)) {
      throw ArgumentError('Resource name cannot contain "$_pathSeparator"');
    }
    if (resourceName.contains(' ')) {
      throw ArgumentError('Resource name cannot contain spaces');
    }
    if (resourceName != resourceName.toLowerCase()) {
      throw ArgumentError('Resource name must be lowercase');
    }
  }

  @override
  bool get requiresDownload => false;

  @override
  bool get supportsProgress => false; // Instant access

  @override
  bool get supportsResume => false;

  @override
  bool validateLoraSource(ModelSource loraSource) => loraSource is BundledSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundledSource && other.resourceName == resourceName;

  @override
  int get hashCode => resourceName.hashCode;

  @override
  String toString() => 'BundledSource(resourceName: $resourceName)';
}

/// File source - external files (mobile only)
final class FileSource extends ModelSource {
  final String path;

  FileSource(this.path) {
    if (kIsWeb) {
      throw UnsupportedError('File sources are not supported on web platform');
    }
    if (path.isEmpty) {
      throw ArgumentError('File path cannot be empty');
    }
    if (!path.startsWith(_pathSeparator)) {
      throw ArgumentError('File path must be absolute (start with $_pathSeparator)');
    }
  }

  @override
  bool get requiresDownload => false;

  @override
  bool get supportsProgress => false;

  @override
  bool get supportsResume => false;

  @override
  bool validateLoraSource(ModelSource loraSource) => loraSource is FileSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FileSource && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileSource(path: $path)';
}
