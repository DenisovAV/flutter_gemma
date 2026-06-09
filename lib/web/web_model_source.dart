// Part of flutter_gemma_web.dart so this file can see [WebModelManager]
// (which itself is a part of the same library) without circular imports.
// Engine-side consumers ([LiteRtLmWebInferenceModel]) import this through
// the parent library re-export.
part of 'flutter_gemma_web.dart';

/// Result of resolving an active web model into a form an engine
/// (MediaPipe `LlmInference` OR `@litert-lm/core` `Engine`) can consume.
///
/// Both engines accept either a URL string (`blob:`/`https:`) or a JS
/// `ReadableStream` / `ReadableStreamDefaultReader`. This sealed type
/// encodes that choice once so engine-specific glue stays trivial.
sealed class WebModelSource {
  const WebModelSource();
}

/// `WebStorageMode.cacheApi` / `WebStorageMode.none` path. [url] is a
/// `blob:` URL produced by `WebCacheService` / `BlobUrlManager`, or an
/// `https:` URL when caching is disabled.
final class BlobUrlModelSource extends WebModelSource {
  const BlobUrlModelSource(this.url);
  final String url;
}

/// `WebStorageMode.streaming` + `opfs://<filename>` path. Carries the
/// [WebOPFSService] and the OPFS filename so each engine can ask for
/// the form it consumes — MediaPipe wants a
/// `ReadableStreamDefaultReader`, `@litert-lm/core` wants the raw
/// `ReadableStream`.
final class OpfsStreamModelSource extends WebModelSource {
  const OpfsStreamModelSource(this.opfsService, this.filename);
  final WebOPFSService opfsService;
  final String filename;

  /// `ReadableStreamDefaultReader` — used by MediaPipe's
  /// `LlmInferenceBaseOptions.modelAssetBuffer`.
  Future<JSAny> openReader() => opfsService.getStreamReader(filename);

  /// Raw `ReadableStream` — used by `@litert-lm/core`'s
  /// `Engine.create({model: <ReadableStream>})`.
  Future<JSAny> openStream() => opfsService.getStream(filename);
}

/// Resolves the active inference model from [WebModelManager] into the
/// correct [WebModelSource] subtype based on [ServiceRegistry]
/// `useStreamingStorage` and the resolved path prefix. This is the
/// single piece of code that decides blob-URL vs OPFS-stream — both
/// `WebInferenceModel` (MediaPipe) and `LiteRtLmWebInferenceModel`
/// (`@litert-lm/core`) consume it.
class WebModelSourceResolver {
  WebModelSourceResolver(this._modelManager);
  final WebModelManager _modelManager;

  /// Resolves the active inference model. Returns the source plus the
  /// installed LoRA path if any (only meaningful for MediaPipe; LiteRT-LM
  /// throws on `loraPath`).
  Future<({WebModelSource model, String? loraPath})>
      resolveActiveInferenceModel() async {
    final active = _modelManager.activeInferenceModel;
    if (active == null) {
      throw StateError(
        'No active inference model set. Use FlutterGemma.installModel() first.',
      );
    }
    final paths = await _modelManager.getModelFilePaths(active);
    if (paths == null || paths.isEmpty) {
      throw StateError('Model file paths not found for active model.');
    }
    final raw = paths[PreferencesKeys.installedModelFileName];
    if (raw == null) {
      throw StateError('Model path not found in file paths.');
    }
    final lora = paths[PreferencesKeys.installedLoraFileName];
    final source = await _toSource(raw);
    return (model: source, loraPath: lora);
  }

  Future<WebModelSource> _toSource(String raw) async {
    final registry = ServiceRegistry.instance;
    if (registry.useStreamingStorage && raw.startsWith('opfs://')) {
      final filename = raw.substring('opfs://'.length);
      final downloadService = registry.downloadService;
      if (downloadService is! WebDownloadService) {
        throw StateError('Expected WebDownloadService for web platform.');
      }
      final opfs = downloadService.opfsService;
      if (opfs == null) {
        throw StateError(
            'OPFS service not available (streaming mode requires OPFS).');
      }
      if (kDebugMode) {
        gemmaLog('[WebModelSourceResolver] OPFS stream source for: $filename');
      }
      return OpfsStreamModelSource(opfs, filename);
    }
    if (kDebugMode) {
      gemmaLog('[WebModelSourceResolver] Blob/HTTPS URL: $raw');
    }
    return BlobUrlModelSource(raw);
  }
}
