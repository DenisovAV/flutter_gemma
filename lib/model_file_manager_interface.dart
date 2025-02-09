abstract class ModelFileManager {
  /// Whether the model is installed (i.e. downloaded, copied from assets or path to the file is set manually)
  /// and ready to be initialized and used.
  Future<bool> get isModelInstalled;

  /// Whether the lora weights are installed (i.e. downloaded, copied from assets or path to the file is set manually)
  /// and ready to use.
  Future<bool> get isLoraInstalled;

  /// Sets the path to the model and lora weights files and installs them.
  /// Use this method to manage the files manually.
  ///
  /// {@macro gemma.load_model}
  Future<void> setModelPath(String path, {String? loraPath});

  /// Sets the path to the lora weights file.
  /// Use this method to manage the lora weights file manually.
  ///
  /// {@macro gemma.load_weights}
  Future<void> setLoraWeightsPath(String path);

  /// Downloads the model and lora weights from the network and installs them.
  ///
  /// {@template gemma.load_model}
  /// Model should be loaded before initialization.
  ///
  /// This method can be safely called multiple times. Model and lora weights will be loaded only if they doesn't exist.
  ///
  /// To reload the model, call [deleteModel] first. To reload the lora weights, call [deleteLoraWeights] first.
  /// {@endtemplate}
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl});

  /// Downloads the model and lora weights from the network and installs it with progress.
  ///
  /// {@macro gemma.load_model}
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl});

  /// Downloads the lora weights from the network and installs it.
  ///
  /// {@template gemma.load_weights}
  /// This method can be safely called multiple times. Lora weights will be loaded only if they doesn't exist.
  ///
  /// To reload the lora weights, call [deleteLoraWeights] first.
  /// {@endtemplate}
  Future<void> downloadLoraWeightsFromNetwork(String loraUrl);

  /// Installs the model and lora weights from the asset.
  ///
  /// {@macro gemma.load_model}
  ///
  /// {@template gemma.asset_model}
  /// This method should be used only for development purpose.
  /// Never embed neither model nor lora weights in the production app.
  /// {@endtemplate}
  Future<void> installModelFromAsset(String path, {String? loraPath});

  /// Installs the lora weights from the asset.
  ///
  /// {@macro gemma.load_weights}
  ///
  /// {@macro gemma.asset_model}
  Future<void> installLoraWeightsFromAsset(String path);

  /// Installs the model and lora weights from the asset with progress.
  ///
  /// {@macro gemma.load_model}
  ///
  /// {@macro gemma.asset_model}
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath});

  /// Deletes the loaded model from storage and uninstalls it.
  /// If model was installed using the [setModelPath] method, it will only be uninstalled.
  ///
  /// Nothing happens if the model is not loaded.
  ///
  /// Also, closes the inference if it is initialized.
  Future<void> deleteModel();

  /// Deletes the loaded lora weights. Nothing happens if the lora weights are not loaded.
  ///
  /// Also, closes the inference if it is initialized.
  Future<void> deleteLoraWeights();
}
