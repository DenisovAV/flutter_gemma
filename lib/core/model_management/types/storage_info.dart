part of '../../../mobile/flutter_gemma_mobile.dart';

/// Information about a potentially orphaned file
class OrphanedFileInfo {
  final String filename;
  final String path;
  final int sizeBytes;
  final DateTime? lastModified;

  const OrphanedFileInfo({
    required this.filename,
    required this.path,
    required this.sizeBytes,
    this.lastModified,
  });

  double get sizeMB => sizeBytes / (1024 * 1024);

  @override
  String toString() => '$filename (${sizeMB.toStringAsFixed(2)} MB)';
}

/// Storage statistics
class StorageStats {
  final int totalFiles;
  final int totalSizeBytes;
  final List<OrphanedFileInfo> orphanedFiles;

  const StorageStats({
    required this.totalFiles,
    required this.totalSizeBytes,
    required this.orphanedFiles,
  });

  int get orphanedFilesSize =>
    orphanedFiles.fold(0, (sum, f) => sum + f.sizeBytes);

  double get totalSizeMB => totalSizeBytes / (1024 * 1024);
  double get orphanedSizeMB => orphanedFilesSize / (1024 * 1024);

  @override
  String toString() {
    return 'StorageStats:\n'
        '  Total files: $totalFiles (${totalSizeMB.toStringAsFixed(2)} MB)\n'
        '  Orphaned files: ${orphanedFiles.length} (${orphanedSizeMB.toStringAsFixed(2)} MB)';
  }
}
