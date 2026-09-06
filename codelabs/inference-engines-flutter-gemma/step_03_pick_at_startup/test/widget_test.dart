import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';

void main() {
  test('every downloaded model id matches the last segment of its URL', () {
    for (final model in [Models.gemma3, Models.qwen3]) {
      expect(model.id, model.url!.split('/').last, reason: model.label);
    }
  });

  // `flutter test` pins `defaultTargetPlatform` to android (Flutter's own
  // `_platform_io.dart` does that whenever FLUTTER_TEST is set), so this only
  // ever exercises the Gemini Nano arm; the Apple and UnsupportedError arms of
  // `Models.builtIn` are covered by running the app, not by this suite.
  test('the built-in model has no file and routes to the built-in engine', () {
    final m = Models.builtIn;
    expect(m.url, isNull);
    expect(m.fileType, ModelFileType.builtIn);
    expect(m.isBuiltIn, isTrue);
  });

  testWidgets('the setup screen names the model before any plugin call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(model: Models.qwen3, onReady: () {}),
      ),
    );
    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    expect(find.text('Download model'), findsOneWidget);
  });
}
