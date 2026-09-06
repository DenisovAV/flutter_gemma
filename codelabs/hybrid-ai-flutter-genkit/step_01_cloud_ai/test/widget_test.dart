import 'package:flutter_test/flutter_test.dart';
import 'package:workshop_genkit_flutter_hybrid_ai/main.dart';

void main() {
  // `CloudAIService.initialize()` throws when GEMINI_API_KEY was not passed
  // with --dart-define, which is exactly how this test runs. The screen
  // catches it, so a missing key must cost the banner and nothing else.
  testWidgets('a missing GEMINI_API_KEY still leaves a usable chat', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Connecting to cloud AI...'), findsOneWidget);

    await tester.pump();
    expect(find.text('Connecting to cloud AI...'), findsNothing);
    expect(find.text('Send a message to start chatting'), findsOneWidget);
  });
}
