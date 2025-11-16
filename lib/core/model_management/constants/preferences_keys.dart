/// Centralized SharedPreferences keys for model management
///
/// SINGLE SOURCE OF TRUTH for all preference keys used by the plugin
class PreferencesKeys {
  // Private constructor to prevent instantiation
  PreferencesKeys._();

  // ============================================================================
  // Multi-model lists (NEW system - supports multiple models)
  // ============================================================================

  /// List<String> of installed inference model files
  static const String installedModels = 'installed_models';

  /// List<String> of installed LoRA files
  static const String installedLoras = 'installed_loras';

  /// List<String> of installed embedding model files
  static const String installedEmbeddingModels = 'installed_embedding_models';

  /// List<String> of installed tokenizer files
  static const String installedTokenizers = 'installed_tokenizers';

  // ============================================================================
  // Legacy single-value keys (OLD system - backward compatibility)
  // ============================================================================

  /// Legacy: Single inference model filename
  static const String installedModelFileName = 'installed_model_file_name';

  /// Legacy: Single LoRA filename
  static const String installedLoraFileName = 'installed_lora_file_name';

  /// Legacy: Single embedding model filename
  static const String embeddingModelFile = 'embedding_model_file';

  /// Legacy: Single tokenizer filename
  static const String embeddingTokenizerFile = 'embedding_tokenizer_file';

  // ============================================================================
  // Path mappings (dynamic keys with filename)
  // ============================================================================

  /// Get key for bundled file path mapping
  /// Format: 'bundled_path_{filename}'
  static String bundledPath(String filename) => 'bundled_path_$filename';

  /// Get key for external file path mapping
  /// Format: 'external_path_{filename}'
  static String externalPath(String filename) => 'external_path_$filename';

  // ============================================================================
  // Web Cache Management (Cache API metadata)
  // ============================================================================

  /// Prefix for web cache metadata keys
  /// Format: 'web_cache_{url.hashCode}'
  static const String webCacheMetadataPrefix = 'web_cache_';

  /// Whether persistent storage was granted
  static const String webCachePersistentGranted = 'web_cache_persistent_granted';

  /// Last cache cleanup timestamp
  static const String webCacheLastCleanup = 'web_cache_last_cleanup';
}
