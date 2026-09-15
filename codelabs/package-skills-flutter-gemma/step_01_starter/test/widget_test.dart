import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_skills/main.dart';

void main() {
  testWidgets('the starter runs and leaves the work to the assistant', (
    tester,
  ) async {
    await tester.pumpWidget(const SkillsApp());
    expect(
      find.textContaining('Ask your coding assistant to build the chat'),
      findsOneWidget,
    );
  });
}
