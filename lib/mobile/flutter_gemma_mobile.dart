import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../flutter_gemma.dart';

part 'flutter_gemma_mobile_model_manager.dart';
part 'flutter_gemma_mobile_inference_model.dart';

@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

final _platformService = PlatformService();

class FlutterGemma extends FlutterGemmaPlugin {
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;

  @override
  late final MobileModelManager modelManager = MobileModelManager(
    onDeleteModel: _closeModelBeforeDeletion,
    onDeleteLora: _closeModelBeforeDeletion,
  );

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  Future<InferenceModel> createModel({
    required bool isInstructionTuned,
    int maxTokens = 1024,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModel>();
    final (isModelInstalled, isLoraInstalled, modelFile, loraFile) = await (
      modelManager.isModelInstalled,
      modelManager.isLoraInstalled,
      modelManager._modelFile,
      modelManager._loraFile,
    ).wait;
    if (isModelInstalled) {
      try {
        await _platformService.createModel(
          maxTokens: maxTokens,
          modelPath: modelFile.path,
          loraRanks: supportedLoraRanks,
        );
        final model = _initializedModel = MobileInferenceModel(
          maxTokens: maxTokens,
          isInstructionTuned: true,
          modelManager: modelManager,
          onClose: () {
            _initializedModel = null;
            _initCompleter = null;
          },
        );
        completer.complete(model);
        return model;
      } catch (e, st) {
        completer.completeError(e, st);
        Error.throwWithStackTrace(e, st);
      }
    } else {
      throw Exception(
        'Gemma Model is not installed yet. Use the `modelManager` to load the model first',
      );
    }
  }

  Future<void> _closeModelBeforeDeletion() {
    return _initializedModel?.close() ?? Future.value();
  }
}
