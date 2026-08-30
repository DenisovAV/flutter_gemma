import 'dart:convert';

import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver, ResolvedHfFile, ResolvedHfModel;
import 'package:flutter_gemma/core/utils/file_name_utils.dart'
    show FileNameUtils;

import 'hf/hf_fetch_types.dart';
import 'hf/hf_fetch_web.dart' if (dart.library.io) 'hf/hf_fetch_io.dart';

/// [HuggingFaceResolver] for ONNX (ORT-GenAI) models.
///
/// An ORT-GenAI model is a DIRECTORY — `genai_config.json` + `model.onnx`
/// (+ `model.onnx_data` for external weights) + tokenizer files — and a repo
/// usually ships several execution-provider (EP) variants, one per subfolder
/// (`cpu_and_mobile/…`, `cuda/…`, …). On NATIVE this resolver lists the repo
/// via the Hugging Face tree API, picks one EP folder, and returns every file
/// in it as a directory [ResolvedHfModel] (`files` + `directoryName`) — core's
/// directory-install path then downloads them into a per-model subdirectory.
///
/// On WEB, ONNX generation is fileless (Transformers.js owns the repo id and
/// caches it itself), so this returns a single-file/`files == null` model whose
/// `NetworkSource` URL maps to the repo id — the existing web install path
/// handles it, no filesystem needed.
///
/// EP selection: pass [variant] (the exact folder, e.g.
/// `cpu_and_mobile/cpu-int4-…`) to pin one; otherwise it is chosen from
/// `preferredBackend` — a GPU folder (`cuda`/`dml`/`coreml`) when GPU is
/// requested and present, else a CPU/mobile folder, else the sole variant.
/// **v1 note:** GPU-EP *selection* is wired, but on-device GPU execution is not
/// bundled yet — the model still runs on CPU.
///
/// Auto-registered from `OnnxEngine` (which implements
/// `HuggingFaceResolverSource`), so registering the engine is enough; pass an
/// explicit `OnnxHuggingFaceResolver(variant: …)` to
/// `FlutterGemma.initialize(huggingFaceResolvers: [...])` only to override.
class OnnxHuggingFaceResolver implements HuggingFaceResolver {
  /// [variant] pins an exact EP subfolder (skips the backend heuristic).
  /// [revision] is the repo revision to pin (default `main`). [fetch] is a
  /// test/app seam for the HTTP GET; null uses the platform default (`dart:io`
  /// [HttpClient] natively, the browser's `fetch` on web).
  const OnnxHuggingFaceResolver({
    String? variant,
    String revision = 'main',
    HfFetch? fetch,
  }) : _variant = variant,
       _revision = revision,
       _fetch = fetch;

  final String? _variant;
  final String _revision;
  final HfFetch? _fetch;

  @override
  String get name => 'onnx-huggingface';

  @override
  int get priority => 0;

  @override
  bool canResolve(String repo, {ModelFileType? fileType}) =>
      fileType == ModelFileType.onnx;

  @override
  Future<ResolvedHfModel> resolve(
    String repo, {
    String? token,
    String? platform,
    PreferredBackend? preferredBackend,
  }) async {
    if (repo.trim().isEmpty) {
      throw ArgumentError.value(repo, 'repo', 'must be a non-empty "org/name"');
    }

    // WEB: ONNX generation is fileless (Transformers.js resolves + caches the
    // repo from its id). Return a files==null model whose NetworkSource URL maps
    // to the repo id (see transformers_repo_id.dart); the web install path uses
    // it directly, and no directory download is attempted (there is no FS).
    if (platform == 'web') {
      return ResolvedHfModel(
        file: repo.split('/').last,
        url: 'https://huggingface.co/$repo',
        fileType: ModelFileType.onnx,
      );
    }

    final fetch = _fetch ?? defaultHfFetch;
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    // List the repo's file tree (recursive; one page is enough for the handful
    // of files an ORT-GenAI model ships — limit guards a many-variant repo).
    final treeUrl = Uri.parse(
      'https://huggingface.co/api/models/$repo/tree/$_revision'
      '?recursive=true&limit=1000',
    );
    final String body;
    try {
      body = await fetch(treeUrl, headers);
    } on HfFetchException catch (e) {
      if (e.statusCode == 404) {
        throw StateError(
          'Hugging Face repo "$repo" (revision "$_revision") was not found, or '
          'its file tree is not accessible${token == null ? " — a gated repo "
                    "needs a token" : ""}.',
        );
      }
      rethrow;
    }

    final filePaths = <String>[
      for (final e in (jsonDecode(body) as List).cast<Map<String, dynamic>>())
        if (e['type'] == 'file') e['path'] as String,
    ];

    // Folders that contain a genai_config.json — the ORT-GenAI signal. '' means
    // the repo root.
    const marker = 'genai_config.json';
    final configFolders = <String>[
      for (final p in filePaths)
        if (p == marker)
          ''
        else if (p.endsWith('/$marker'))
          p.substring(0, p.length - marker.length - 1),
    ];
    if (configFolders.isEmpty) {
      throw StateError(
        'Hugging Face repo "$repo" has no genai_config.json — it is not an '
        'ORT-GenAI model directory. Install a repo that ships an ORT-GenAI '
        'export (genai_config.json + model.onnx + tokenizer).',
      );
    }

    final folder = _pickFolder(
      configFolders,
      preferredBackend: preferredBackend,
      repo: repo,
    );
    final prefix = folder.isEmpty ? '' : '$folder/';

    // The chosen folder's DIRECT children (ORT-GenAI folders are flat).
    final members = <String>[
      for (final p in filePaths)
        if (p.startsWith(prefix) && !p.substring(prefix.length).contains('/'))
          p,
    ];

    String urlFor(String path) {
      final encoded = path.split('/').map(Uri.encodeComponent).join('/');
      return 'https://huggingface.co/$repo/resolve/$_revision/$encoded';
    }

    final files = <ResolvedHfFile>[
      for (final p in members)
        ResolvedHfFile(name: p.substring(prefix.length), url: urlFor(p)),
    ];

    final notes = <String>[
      'Resolved ORT-GenAI directory "${folder.isEmpty ? "(repo root)" : folder}"'
          ' (${files.length} files).',
      if (preferredBackend == PreferredBackend.gpu)
        'GPU was requested; ORT-GenAI on-device GPU execution is not bundled '
            'yet — the model runs on CPU regardless of the chosen variant.',
    ];

    return ResolvedHfModel(
      file: marker, // the primary the engine loads from
      url: urlFor('${prefix}genai_config.json'),
      fileType: ModelFileType.onnx,
      files: files,
      directoryName: FileNameUtils.sanitizeHfDirName(
        repo,
        variant: folder.isEmpty ? null : folder,
      ),
      notes: List.unmodifiable(notes),
    );
  }

  /// Picks the EP folder among [folders] (each a path that holds a
  /// genai_config.json). An explicit [variant] wins; otherwise a GPU folder for
  /// a GPU request, else a CPU/mobile folder, else the sole/first variant.
  String _pickFolder(
    List<String> folders, {
    required PreferredBackend? preferredBackend,
    required String repo,
  }) {
    if (_variant != null) {
      if (!folders.contains(_variant)) {
        throw ArgumentError.value(
          _variant,
          'variant',
          'has no genai_config.json in "$repo" (available: '
              '${folders.map((f) => f.isEmpty ? "(root)" : f).join(", ")})',
        );
      }
      return _variant;
    }
    if (folders.length == 1) return folders.first;

    final wantGpu = preferredBackend == PreferredBackend.gpu;
    final preferred = folders.where(wantGpu ? _looksGpu : _looksCpu).toList();
    if (preferred.isNotEmpty) return preferred.first;
    // Requested backend has no folder → prefer any CPU/mobile build, else first.
    final cpu = folders.where(_looksCpu).toList();
    return cpu.isNotEmpty ? cpu.first : folders.first;
  }

  static final _gpuRe = RegExp(
    r'cuda|dml|directml|coreml|gpu',
    caseSensitive: false,
  );
  static final _cpuRe = RegExp(r'cpu|mobile', caseSensitive: false);

  static bool _looksGpu(String folder) => _gpuRe.hasMatch(folder);
  static bool _looksCpu(String folder) => _cpuRe.hasMatch(folder);
}
