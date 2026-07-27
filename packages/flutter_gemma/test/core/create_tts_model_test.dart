import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('createTtsModel throws StateError when no active TTS model', () {
    final plugin = FlutterGemmaMobile();
    expect(plugin.createTtsModel(), throwsA(isA<StateError>()));
  });
}
