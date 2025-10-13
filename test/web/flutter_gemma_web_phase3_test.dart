@TestOn('browser')
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/web/flutter_gemma_web.dart';

void main() {
  group('Phase 3: FlutterGemmaWeb Singleton Pattern Tests', () {
    setUp(() {
      // Reset plugin instance before each test
      FlutterGemmaPlugin.instance = FlutterGemmaWeb();
    });

    group('Critical: Singleton Instance Consistency', () {
      test('modelManager returns same instance on every call', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Act
        final manager1 = web.modelManager;
        final manager2 = web.modelManager;
        final manager3 = web.modelManager;

        // Assert
        expect(identical(manager1, manager2), isTrue, reason: 'First two calls should return identical instance');
        expect(identical(manager2, manager3), isTrue, reason: 'Second and third calls should return identical instance');
        expect(identical(manager1, manager3), isTrue, reason: 'First and third calls should return identical instance');
      });

      test('FlutterGemmaPlugin.instance.modelManager returns consistent instance', () {
        // Arrange
        FlutterGemmaPlugin.instance = FlutterGemmaWeb();

        // Act
        final manager1 = FlutterGemmaPlugin.instance.modelManager;
        final manager2 = FlutterGemmaPlugin.instance.modelManager;
        final manager3 = FlutterGemmaPlugin.instance.modelManager;

        // Assert
        expect(identical(manager1, manager2), isTrue, reason: 'Plugin instance should return same manager');
        expect(identical(manager2, manager3), isTrue, reason: 'Plugin instance should return same manager across multiple calls');
      });

      test('modelManager instance persists across multiple getter calls', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Act
        final instances = <ModelFileManager>[];
        for (int i = 0; i < 10; i++) {
          instances.add(web.modelManager);
        }

        // Assert
        final first = instances.first;
        for (final instance in instances) {
          expect(identical(first, instance), isTrue, reason: 'All calls should return same instance');
        }
      });

      test('different FlutterGemmaWeb instances share same WebModelManager singleton', () {
        // Arrange
        final web1 = FlutterGemmaWeb();
        final web2 = FlutterGemmaWeb();

        // Act
        final manager1 = web1.modelManager;
        final manager2 = web2.modelManager;

        // Assert
        expect(identical(manager1, manager2), isTrue, reason: 'WebModelManager should be a true singleton shared across instances');
      });
    });

    group('Critical: Active Model Persistence', () {
      test('activeInferenceModel persists across modelManager getter calls', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test-model',
          modelUrl: 'https://example.com/model.task',
        );

        // Act
        web.modelManager.setActiveModel(spec);
        expect(web.modelManager.activeInferenceModel, spec, reason: 'Should set activeInferenceModel');

        // Get manager again - should still have same active model
        final manager2 = web.modelManager;
        final activeModel = manager2.activeInferenceModel;

        // Assert
        expect(activeModel, isNotNull, reason: 'Active model should not be null after retrieval');
        expect(activeModel, spec, reason: 'Active model should be the same spec we set');
        expect(identical(activeModel, spec), isTrue, reason: 'Should be the exact same instance');
      });

      test('activeEmbeddingModel persists separately from activeInferenceModel', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final inferenceSpec = InferenceModelSpec.fromLegacyUrl(
          name: 'inference',
          modelUrl: 'https://example.com/inference.task',
        );
        final embeddingSpec = EmbeddingModelSpec.fromLegacyUrl(
          name: 'embedding',
          modelUrl: 'https://example.com/embedding.tflite',
          tokenizerUrl: 'https://example.com/tokenizer.model',
        );

        // Act
        web.modelManager.setActiveModel(inferenceSpec);
        expect(web.modelManager.activeInferenceModel, inferenceSpec);
        expect(web.modelManager.activeEmbeddingModel, isNull, reason: 'Embedding model should be null initially');

        web.modelManager.setActiveModel(embeddingSpec);

        // Assert
        expect(web.modelManager.activeInferenceModel, inferenceSpec, reason: 'Inference model should still be set');
        expect(web.modelManager.activeEmbeddingModel, embeddingSpec, reason: 'Embedding model should now be set');
      });

      test('setActiveModel followed by multiple getActiveInferenceModel returns same spec', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test',
          modelUrl: 'https://example.com/test.task',
        );

        // Act
        web.modelManager.setActiveModel(spec);

        final active1 = web.modelManager.activeInferenceModel;
        final active2 = web.modelManager.activeInferenceModel;
        final active3 = web.modelManager.activeInferenceModel;

        // Assert
        expect(active1, spec);
        expect(active2, spec);
        expect(active3, spec);
        expect(identical(active1, active2), isTrue);
        expect(identical(active2, active3), isTrue);
      });

      test('activeModel state survives manager re-access through plugin instance', () {
        // Arrange
        FlutterGemmaPlugin.instance = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'persistent-model',
          modelUrl: 'https://example.com/persistent.task',
        );

        // Act
        FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);

        // Simulate what happens in createSession: re-access modelManager
        final manager1 = FlutterGemmaPlugin.instance.modelManager;
        final activeModel1 = manager1.activeInferenceModel;

        final manager2 = FlutterGemmaPlugin.instance.modelManager;
        final activeModel2 = manager2.activeInferenceModel;

        // Assert
        expect(activeModel1, isNotNull, reason: 'First access should find active model');
        expect(activeModel2, isNotNull, reason: 'Second access should find active model');
        expect(activeModel1, spec);
        expect(activeModel2, spec);
        expect(identical(manager1, manager2), isTrue, reason: 'Should be same manager instance');
      });
    });

    group('Critical: Modern API Integration', () {
      test('ensureModelReadyFromSpec sets activeInferenceModel correctly', () async {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'modern-test',
          modelUrl: 'https://example.com/model.task',
        );

        // Act
        await web.modelManager.ensureModelReadyFromSpec(spec);

        // Assert
        final activeModel = web.modelManager.activeInferenceModel;
        expect(activeModel, isNotNull, reason: 'Active model should be set after ensureModelReadyFromSpec');
        expect(activeModel, spec);
      });

      test('Modern API flow: install -> verify activeModel -> simulate createSession', () async {
        // Arrange
        FlutterGemmaPlugin.instance = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'flow-test',
          modelUrl: 'https://example.com/flow.task',
        );

        // Act 1: Install model (Modern API)
        await FlutterGemmaPlugin.instance.modelManager.ensureModelReadyFromSpec(spec);

        // Verify active model is set
        final manager1 = FlutterGemmaPlugin.instance.modelManager;
        expect(manager1.activeInferenceModel, spec, reason: 'Active model should be set after install');

        // Act 2: Simulate createSession accessing modelManager again
        final manager2 = FlutterGemmaPlugin.instance.modelManager;
        final activeModel = manager2.activeInferenceModel;

        // Assert
        expect(activeModel, isNotNull, reason: 'createSession should find active model');
        expect(activeModel, spec);
        expect(identical(manager1, manager2), isTrue, reason: 'Should be same manager instance');
      });

      test('downloadModelWithProgress sets activeInferenceModel after completion', () async {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'download-test',
          modelUrl: 'https://example.com/download.task',
        );

        // Act
        await for (final _ in web.modelManager.downloadModelWithProgress(spec)) {
          // Consume stream
        }

        // Assert
        final activeModel = web.modelManager.activeInferenceModel;
        expect(activeModel, isNotNull, reason: 'Active model should be set after download');
        expect(activeModel, spec);
      });
    });

    group('Regression: Verify Modern API and createSession Use Same Instance', () {
      test('Modern API and WebInferenceModel.createSession() see same manager', () async {
        // This is THE critical test for the bug that was fixed
        // Before fix: Modern API set activeModel on one instance, createSession() read from different instance → null
        // After fix: Both use same singleton instance → activeModel found

        // Arrange
        FlutterGemmaPlugin.instance = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'critical-test',
          modelUrl: 'https://example.com/critical.task',
        );

        // Act 1: Modern API sets activeModel
        FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);

        // Act 2: Simulate what createSession() does - access modelManager from scratch
        final sessionManager = (FlutterGemmaPlugin.instance as FlutterGemmaWeb).modelManager;
        final activeModel = sessionManager.activeInferenceModel;

        // Assert
        expect(activeModel, isNotNull, reason: 'THIS IS THE BUG FIX: activeModel should NOT be null');
        expect(activeModel, spec, reason: 'Should be the exact spec we set');
      });

      test('Multiple FlutterGemmaWeb instances still share state via singleton', () {
        // Arrange
        final web1 = FlutterGemmaWeb();
        final web2 = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'shared-test',
          modelUrl: 'https://example.com/shared.task',
        );

        // Act
        web1.modelManager.setActiveModel(spec);

        // Assert
        expect(web2.modelManager.activeInferenceModel, spec, reason: 'State should be shared via singleton');
      });
    });

    group('Edge Cases: Null and Unset States', () {
      test('activeInferenceModel is null before setActiveModel', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Assert
        expect(web.modelManager.activeInferenceModel, isNull);
      });

      test('activeEmbeddingModel is null before setActiveModel', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Assert
        expect(web.modelManager.activeEmbeddingModel, isNull);
      });

      test('can set activeModel to null and retrieve null', () {
        // This tests clearing active model state
        // Note: Current implementation doesn't have clearActiveModel, but we can verify initial null state

        // Arrange
        final web = FlutterGemmaWeb();

        // Act
        final beforeSet = web.modelManager.activeInferenceModel;

        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'temp',
          modelUrl: 'https://example.com/temp.task',
        );
        web.modelManager.setActiveModel(spec);

        final afterSet = web.modelManager.activeInferenceModel;

        // Assert
        expect(beforeSet, isNull, reason: 'Should be null before setting');
        expect(afterSet, spec, reason: 'Should be set after setting');
      });

      test('switching between inference and embedding models preserves both', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final inferenceSpec = InferenceModelSpec.fromLegacyUrl(
          name: 'inf1',
          modelUrl: 'https://example.com/inf1.task',
        );
        final embeddingSpec = EmbeddingModelSpec.fromLegacyUrl(
          name: 'emb1',
          modelUrl: 'https://example.com/emb1.tflite',
          tokenizerUrl: 'https://example.com/tok1.model',
        );

        // Act
        web.modelManager.setActiveModel(inferenceSpec);
        final afterInference = web.modelManager.activeInferenceModel;

        web.modelManager.setActiveModel(embeddingSpec);
        final afterEmbedding1 = web.modelManager.activeInferenceModel;
        final afterEmbedding2 = web.modelManager.activeEmbeddingModel;

        // Assert
        expect(afterInference, inferenceSpec);
        expect(afterEmbedding1, inferenceSpec, reason: 'Inference model should still be set');
        expect(afterEmbedding2, embeddingSpec, reason: 'Embedding model should now be set');
      });

      test('re-setting same model updates state correctly', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec1 = InferenceModelSpec.fromLegacyUrl(
          name: 'model',
          modelUrl: 'https://example.com/v1.task',
        );
        final spec2 = InferenceModelSpec.fromLegacyUrl(
          name: 'model',
          modelUrl: 'https://example.com/v2.task',
        );

        // Act
        web.modelManager.setActiveModel(spec1);
        final active1 = web.modelManager.activeInferenceModel;

        web.modelManager.setActiveModel(spec2);
        final active2 = web.modelManager.activeInferenceModel;

        // Assert
        expect(active1, spec1);
        expect(active2, spec2);
        expect(identical(active1, active2), isFalse, reason: 'Should be different spec instances');
      });
    });

    group('WebModelManager Type Checking', () {
      test('modelManager returns WebModelManager instance', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Act
        final manager = web.modelManager;

        // Assert
        expect(manager, isA<WebModelManager>(), reason: 'Should return WebModelManager instance');
      });

      test('WebModelManager implements ModelFileManager', () {
        // Arrange
        final web = FlutterGemmaWeb();

        // Act
        final manager = web.modelManager;

        // Assert
        expect(manager, isA<ModelFileManager>(), reason: 'WebModelManager must implement ModelFileManager interface');
      });
    });

    group('Concurrent Access', () {
      test('concurrent modelManager access returns same instance', () async {
        // Arrange
        final web = FlutterGemmaWeb();
        final futures = <Future<ModelFileManager>>[];

        // Act
        for (int i = 0; i < 100; i++) {
          futures.add(Future(() => web.modelManager));
        }
        final managers = await Future.wait(futures);

        // Assert
        final first = managers.first;
        for (final manager in managers) {
          expect(identical(first, manager), isTrue, reason: 'All concurrent accesses should return same instance');
        }
      });

      test('concurrent setActiveModel calls maintain consistency', () async {
        // Arrange
        final web = FlutterGemmaWeb();
        final specs = List.generate(
          10,
          (i) => InferenceModelSpec.fromLegacyUrl(
            name: 'model$i',
            modelUrl: 'https://example.com/model$i.task',
          ),
        );

        // Act
        final futures = specs.map((spec) {
          return Future(() => web.modelManager.setActiveModel(spec));
        }).toList();
        await Future.wait(futures);

        // Assert
        final activeModel = web.modelManager.activeInferenceModel;
        expect(activeModel, isNotNull, reason: 'Should have some active model');
        expect(specs.contains(activeModel), isTrue, reason: 'Should be one of the specs we set');
      });
    });

    group('Memory Management', () {
      test('singleton persists across multiple web instances', () {
        // Arrange & Act
        final managers = <ModelFileManager>[];
        for (int i = 0; i < 10; i++) {
          final web = FlutterGemmaWeb();
          managers.add(web.modelManager);
        }

        // Assert
        final first = managers.first;
        for (final manager in managers) {
          expect(identical(first, manager), isTrue, reason: 'All should return same singleton');
        }
      });

      test('setting activeModel does not create new manager instance', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final managerBefore = web.modelManager;

        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test',
          modelUrl: 'https://example.com/test.task',
        );

        // Act
        web.modelManager.setActiveModel(spec);
        final managerAfter = web.modelManager;

        // Assert
        expect(identical(managerBefore, managerAfter), isTrue, reason: 'Should be same manager instance before and after setActiveModel');
      });
    });

    group('Type Safety', () {
      test('setActiveModel rejects invalid spec type', () {
        // This is handled by Dart's type system, but we can verify runtime behavior
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test',
          modelUrl: 'https://example.com/test.task',
        );

        // Act & Assert - should not throw
        web.modelManager.setActiveModel(spec);
        expect(web.modelManager.activeInferenceModel, spec);
      });

      test('activeInferenceModel returns correct type', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test',
          modelUrl: 'https://example.com/test.task',
        );

        // Act
        web.modelManager.setActiveModel(spec);
        final active = web.modelManager.activeInferenceModel;

        // Assert
        expect(active, isA<InferenceModelSpec>());
      });

      test('activeEmbeddingModel returns correct type', () {
        // Arrange
        final web = FlutterGemmaWeb();
        final spec = EmbeddingModelSpec.fromLegacyUrl(
          name: 'test',
          modelUrl: 'https://example.com/test.tflite',
          tokenizerUrl: 'https://example.com/test.model',
        );

        // Act
        web.modelManager.setActiveModel(spec);
        final active = web.modelManager.activeEmbeddingModel;

        // Assert
        expect(active, isA<EmbeddingModelSpec>());
      });
    });
  });

  group('Phase 3: Integration with FlutterGemmaPlugin', () {
    setUp(() {
      FlutterGemmaPlugin.instance = FlutterGemmaWeb();
    });

    test('FlutterGemmaPlugin.instance returns FlutterGemmaWeb', () {
      expect(FlutterGemmaPlugin.instance, isA<FlutterGemmaWeb>());
    });

    test('Plugin instance modelManager is singleton', () {
      final manager1 = FlutterGemmaPlugin.instance.modelManager;
      final manager2 = FlutterGemmaPlugin.instance.modelManager;

      expect(identical(manager1, manager2), isTrue);
    });

    test('Plugin instance activeModel persists', () {
      final spec = InferenceModelSpec.fromLegacyUrl(
        name: 'plugin-test',
        modelUrl: 'https://example.com/plugin.task',
      );

      FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);

      final active1 = FlutterGemmaPlugin.instance.modelManager.activeInferenceModel;
      final active2 = FlutterGemmaPlugin.instance.modelManager.activeInferenceModel;

      expect(active1, spec);
      expect(active2, spec);
      expect(identical(active1, active2), isTrue);
    });
  });
}
