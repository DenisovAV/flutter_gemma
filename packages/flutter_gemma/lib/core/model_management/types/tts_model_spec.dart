part of '../model_specs.dart';

/// Text-to-speech model families supported by the pluggable TTS backends.
/// [matcha] and [qwen3] have shipped [TtsModelProfile]/pipelines
/// (`flutter_gemma_speech`); [kokoro]/[supertonic] are documented follow-ons
/// (fail-loud until wired).
enum TtsModelType { matcha, supertonic, kokoro, qwen3 }

/// The filenames a given TTS model needs, installed together as a bundle from
/// one source. Fail-loud for unwired families.
extension TtsModelTypeManifest on TtsModelType {
  List<String> get manifest => switch (this) {
    TtsModelType.matcha => const [
      'matcha_textenc_fp16.tflite',
      'matcha_decoder_fp16.tflite',
      'matcha_vocoder_fp16.tflite',
      'dp_g2p_matcha_fp16.tflite',
      'g2p_dict.txt.gz',
      'emb.bin',
      'config.json',
      'g2p_meta.json',
    ],
    // litert-community/Qwen3-TTS-12Hz-0.6B-Base on HuggingFace. Entries are
    // PLAIN basenames — deliberately NOT the `tables/`/`voices/` subpaths
    // those 5 files actually live under on the HF repo (see [urlSuffixFor]).
    // This is load-bearing, not a simplification: [TtsBundleFile.fromSource]
    // derives a file's installed identity (== [TtsBundleFile.prefsKey] ==
    // the `artifactPaths` key `Qwen3TtsCore.load`/`Qwen3Tables.load` read)
    // from the LAST path segment of its source, and
    // `MobileModelManager._restoreActiveTtsModel` independently re-derives
    // the SAME namespaced on-disk path directly from this raw manifest
    // string (`FileNameUtils.namespaced(modelId, fn)`) — if an entry here
    // contained a `/`, those two derivations would silently diverge (fresh
    // install writes the URL-extracted flat basename; restore would look for
    // a namespaced path with an embedded subdirectory) and active-model
    // restore would fail to find the file after every relaunch. No
    // `config.json` — Qwen3's sampling params (top_k=50, temperature=0.9,
    // repetition_penalty=1.05, max_frames=512) are recipe constants threaded
    // as Dart defaults, not model-file-driven.
    TtsModelType.qwen3 => const [
      'talker_int4.tflite',
      'mtp_fp32.tflite',
      'codec_decoder_fp32.tflite',
      'tokenizer.json',
      'text_embedding_fp16.npy',
      'text_projection_fp32.npz',
      'codec_embedding_fp32.npy',
      'mtp_embeddings_fp16.npy',
      'demo_speaker.npy',
    ],
    _ => throw UnimplementedError(
      'TTS manifest for $this is a follow-on (only matcha/qwen3 are wired)',
    ),
  };

  /// The URL path segment a bundle member is actually fetched from under the
  /// model's `resolve/main/` base — usually just [plainFilename] itself, but
  /// [TtsModelType.qwen3]'s 4 embedding-table members and its 1 demo-voice
  /// member live in the HF repo's `tables/`/`voices/` subdirectories even
  /// though (per [manifest]'s doc) their INSTALLED identity is the bare
  /// basename. Safe to add a directory prefix here: it changes ONLY where
  /// [TtsInstallationBuilder] fetches the bytes from, never the on-disk
  /// filename/prefsKey (which [TtsBundleFile.fromSource] derives from the
  /// LAST path segment of the resulting URL — a `tables/` prefix earlier in
  /// the path is dropped exactly like the plain-basename manifest entry
  /// intends). A no-op (identity) for every other [TtsModelType].
  String urlSuffixFor(String plainFilename) {
    if (this != TtsModelType.qwen3) return plainFilename;
    const tableFiles = {
      'text_embedding_fp16.npy',
      'text_projection_fp32.npz',
      'codec_embedding_fp32.npy',
      'mtp_embeddings_fp16.npy',
    };
    if (tableFiles.contains(plainFilename)) return 'tables/$plainFilename';
    if (plainFilename == 'demo_speaker.npy') return 'voices/$plainFilename';
    return plainFilename;
  }
}

/// One file of a TTS model bundle. [filename] is namespaced by the owning
/// [TtsModelType] (every bundle member — including the `.tflite` graphs —
/// since a TTS bundle has no single distinguished "model" file the way
/// Inference/Embedding/STT specs do). [prefsKey] stays the PLAIN manifest
/// basename — NOT the namespaced [filename] — because
/// `flutter_gemma_speech`'s `TtsModelProfile` (e.g. `configFile =
/// 'config.json'`) and `TtsCore`/`MatchaTextFrontend` look bundle paths up
/// by that plain name (`paths[profile.configFile]`); decoupling keeps that
/// cross-package contract intact while the on-disk/repository identity is
/// namespaced.
class TtsBundleFile extends ModelFile {
  final ModelSource _source;
  final String _filename;
  final String _plainFilename;
  TtsBundleFile({
    required ModelSource source,
    required String filename,
    required String plainFilename,
  }) : _source = source,
       _filename = filename,
       _plainFilename = plainFilename;

  /// Creates TtsBundleFile from ModelSource, namespaced by [modelId] — in
  /// practice the owning [TtsModelType]'s name (matcha/kokoro/supertonic).
  ///
  /// The source's extracted basename is NOT restore-safe by itself:
  /// `MobileModelManager._restoreActiveTtsModel` reconstructs the spec from
  /// a `FileSource` whose path basename is already the NAMESPACED on-disk
  /// name (`matcha__config.json`), so the extracted basename may be plain
  /// (fresh install, e.g. NetworkSource) OR already namespaced (restore).
  /// Denamespacing here — symmetric to `FileNameUtils.namespaced`'s
  /// idempotent ADD — keeps `_plainFilename` (and therefore [prefsKey])
  /// ALWAYS the plain manifest basename either way, so
  /// `flutter_gemma_speech`'s `paths[profile.configFile]` lookup (keyed by
  /// the plain name) never breaks on restore.
  factory TtsBundleFile.fromSource(
    ModelSource source, {
    required String modelId,
  }) {
    final extracted = InferenceModelFile._extractFilenameFromSource(source);
    final prefix = '${modelId}__';
    final plain = extracted.startsWith(prefix)
        ? extracted.substring(prefix.length)
        : extracted;
    final filename = FileNameUtils.namespaced(modelId, plain);
    return TtsBundleFile(
      source: source,
      filename: filename,
      plainFilename: plain,
    );
  }
  @override
  ModelSource get source => _source;
  @override
  String get filename => _filename;
  @override
  String get prefsKey => _plainFilename;
  @override
  bool get isRequired => true;

  @override
  int? get minimumSizeBytes {
    // TTS bundles legitimately include small aux files (emb.bin ~137 KB,
    // config/meta json, gzipped dict, qwen3's demo_speaker.npy x-vector
    // ~4 KB). Give those a 1 KB floor; the large .tflite graphs return null
    // and keep the validator's 1 MB default. .npy/.npz also cover qwen3's
    // larger embedding tables — a looser floor for those is accepted so the
    // one genuinely small .npy (demo_speaker.npy) isn't rejected.
    const smallBundleExts = {'.bin', '.gz', '.json', '.npy', '.npz'};
    return smallBundleExts.contains(extension) ? 1024 : null;
  }
}

/// Specification for a TTS model — a SELECTABLE bundle. [ttsModelType] carries
/// the model family so one generic backend dispatches to the right runtime
/// profile; [sources] is one entry per file in that type's manifest.
class TtsModelSpec extends ModelSpec {
  final String _name;
  final List<ModelSource> _sources;
  final TtsModelType _ttsModelType;
  final ModelReplacePolicy _replacePolicy;

  TtsModelSpec({
    required String name,
    required List<ModelSource> sources,
    required TtsModelType ttsModelType,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) : _name = name,
       _sources = sources,
       _ttsModelType = ttsModelType,
       _replacePolicy = replacePolicy;

  /// Builds a spec from the type's [TtsModelTypeManifest.manifest], turning each
  /// filename into a source via [sourceFor] (network URL for install, local file
  /// path for restore).
  factory TtsModelSpec.fromManifest({
    required String name,
    required TtsModelType ttsModelType,
    required ModelSource Function(String filename) sourceFor,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) => TtsModelSpec(
    name: name,
    sources: [for (final fn in ttsModelType.manifest) sourceFor(fn)],
    ttsModelType: ttsModelType,
    replacePolicy: replacePolicy,
  );

  @override
  ModelManagementType get type => ModelManagementType.tts;
  @override
  String get name => _name;
  @override
  ModelReplacePolicy get replacePolicy => _replacePolicy;
  @override
  List<ModelFile> get files => [
    for (final s in _sources)
      TtsBundleFile.fromSource(s, modelId: _ttsModelType.name),
  ];
  List<ModelSource> get sources => List.unmodifiable(_sources);
  TtsModelType get ttsModelType => _ttsModelType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TtsModelSpec) return false;
    if (_name != other._name ||
        _ttsModelType != other._ttsModelType ||
        _replacePolicy != other._replacePolicy ||
        _sources.length != other._sources.length) {
      return false;
    }
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i] != other._sources[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    _name,
    Object.hashAll(_sources),
    _ttsModelType,
    _replacePolicy,
  );
}
