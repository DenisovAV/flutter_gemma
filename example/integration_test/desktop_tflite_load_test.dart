// Smoke test: TFLite C library loads via Native Assets on desktop.
//
// Regression test for #250 follow-up: verifies that the
// `tensorflowlite_c.{dll,so,dylib}` registered in `hook/build.dart` is
// actually placed in the app bundle by the Flutter tool and resolvable
// via `DynamicLibrary.open('tensorflowlite_c')`. No model file required —
// just constructs the bindings.
//
// Run:
//   flutter test integration_test/desktop_tflite_load_test.dart -d macos
//   flutter test integration_test/desktop_tflite_load_test.dart -d windows
//   flutter test integration_test/desktop_tflite_load_test.dart -d linux

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/desktop/tflite/tflite_bindings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TFLite C library loads from Native Assets bundle',
      (WidgetTester tester) async {
    // Constructs DynamicLibrary.open('tensorflowlite_c') under the hood.
    // Throws on platforms where the library is missing (the bug Erik hit
    // on Windows in #250 follow-up: ArgumentError "module could not be
    // found").
    final bindings = TfLiteBindings.load();
    expect(bindings, isNotNull);

    // Sanity-check one symbol resolved (TfLiteModelCreateFromFile is a
    // well-known TFLite C entry point).
    expect(bindings.tfLiteModelCreateFromFile, isNotNull);
  });
}
