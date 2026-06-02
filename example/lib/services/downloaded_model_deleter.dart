import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/services/downloaded_model_loader.dart';
import 'package:flutter_gemma_example/utils/installed_model_lookup.dart';

class DownloadedModelDeleter {
  const DownloadedModelDeleter._();

  static Future<void> delete(String installedId) async {
    if (loadedModelIds().contains(installedId)) {
      await DownloadedModelLoader.unloadAllInMemory();
    }

    final match = resolveCatalog(installedId);
    if (match is EmbeddingMatch && !match.isTokenizer) {
      await FlutterGemma.uninstallModel(installedId);
      final tokenizerId = match.model.tokenizerFilename;
      if (tokenizerId != installedId &&
          await FlutterGemma.isModelInstalled(tokenizerId)) {
        await FlutterGemma.uninstallModel(tokenizerId);
      }
      return;
    }

    await FlutterGemma.uninstallModel(installedId);
  }
}
