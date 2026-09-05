// The web identity-write barrier (#468), exercised in a browser because
// WebModelManager pulls in dart:js_interop and cannot load on the VM.
//
// Run with: flutter test test/web/web_identity_write_barrier_test.dart --platform chrome
// `tool/test_all.sh` runs the VM suites only, so this one is opt-in.
@TestOn('browser')
library;

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/model_management/managers/web_model_manager.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

InferenceModelSpec _spec() => InferenceModelSpec(
  name: 'gemma',
  modelSource: ModelSource.network('https://x/model.litertlm'),
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.litertlm,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a manager built right after setActiveModel sees the whole identity',
    () async {
      // The #468 shape exactly: WebModelSourceResolver.forActiveModel() builds a
      // FRESH manager and rehydrates from prefs. setActiveModel is `void` and can
      // only start the writes, so without the barrier this reader ran while they
      // were still in flight and saw a partial identity -- measured at the time
      // as one key of four -- then threw "No active inference model set" over a
      // model that had just installed successfully.
      //
      // Asserted on prefs rather than on `activeInferenceModel`, which also needs
      // the model FILE to be present; the barrier is about the four identity
      // keys, and all four must be there once ensureInitialized has returned.
      WebModelManager().setActiveModel(_spec());

      await WebModelManager().ensureInitialized();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(PreferencesKeys.activeInferenceModelType),
        isNotNull,
      );
      expect(
        prefs.getString(PreferencesKeys.activeInferenceFileType),
        isNotNull,
      );
      expect(
        prefs.getString(PreferencesKeys.activeInferenceFilename),
        isNotNull,
      );
      expect(prefs.getString(PreferencesKeys.activeInferenceSource), isNotNull);
    },
  );

  test('nothing failed, so no cause is reported', () async {
    WebModelManager().setActiveModel(_spec());
    await WebModelManager().ensureInitialized();

    expect(webIdentityWriteFailure, isNull);
  });
}
