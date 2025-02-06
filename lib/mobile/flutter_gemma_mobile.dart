import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../flutter_gemma.dart';

part 'flutter_gemma_mobile_model_manager.dart';
part 'flutter_gemma_mobile_inference_model.dart';

const _modelPath = 'model.bin';
const _loraPath = 'lora.bin';

@visibleForTesting
const methodChannel = MethodChannel('flutter_gemma');
@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

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
  Future<InferenceModel> init({
    int maxTokens = 1024,
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModel>();
    final (isModelLoaded, isLoraLoaded, modelFile, loraFile) = await (
      modelManager.isModelLoaded,
      modelManager.isLoraLoaded,
      modelManager._modelFile,
      modelManager._loraFile,
    ).wait;
    if (isModelLoaded) {
      try {
        final arguments = {
          'modelPath': modelFile.path,
          'maxTokens': maxTokens,
          'temperature': temperature,
          'randomSeed': randomSeed,
          'topK': topK,
          if (isLoraLoaded) ...{
            'loraPath': loraFile.path,
            'supportedLoraRanks': supportedLoraRanks,
          },
        };

        final result = await methodChannel.invokeMethod<bool>('init', arguments) ?? false;
        if (!result) {
          throw Exception('Initialization failed');
        }
        final model = _initializedModel = MobileInferenceModel(
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
        'Gemma Model is not loaded yet. Use the `modelManager` to load the model first',
      );
    }
  }

  Future<void> _closeModelBeforeDeletion() {
    return _initializedModel?.close() ?? Future.value();
  }
}
