import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('TtsModelType is exported from the public barrel', () {
    // Compile-level check that users can reference the type + install API.
    expect(TtsModelType.matcha.name, 'matcha');
  });

  test('install() requires a base source', () {
    expect(FlutterGemma.installTts().install(), throwsA(isA<StateError>()));
  });

  test('install() requires ofType', () {
    expect(
      FlutterGemma.installTts().fromNetwork('https://x/').install(),
      throwsA(isA<StateError>()),
    );
  });

  test('getActiveTts throws with no active model', () {
    expect(FlutterGemma.getActiveTts(), throwsA(isA<StateError>()));
  });
}
