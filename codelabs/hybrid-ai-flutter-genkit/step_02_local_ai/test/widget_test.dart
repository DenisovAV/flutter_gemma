import 'package:flutter_test/flutter_test.dart';
import 'package:workshop_genkit_flutter_hybrid_ai/services/cloud_ai_service.dart';
import 'package:workshop_genkit_flutter_hybrid_ai/services/local_ai_service.dart';

void main() {
  // Step 2 is two services behind one `AIService` contract. Both refuse to
  // stream before `initialize()` rather than returning an empty stream, so a
  // forgotten init shows up as an error and not as a silently mute chat.
  // Neither test calls `initialize()`: the cloud one needs an API key and the
  // on-device one downloads ~550 MB, so both belong in a device run.
  test('the cloud service refuses to stream before initialize()', () {
    final service = CloudAIService();
    expect(() => service.generateResponseStream('hi').first, throwsStateError);
  });

  test('the on-device service starts uninitialized', () {
    final service = LocalAIService();
    expect(service.isInitialized, isFalse);
    expect(() => service.ai, throwsStateError);
    expect(service.embedderName, 'embedding-gemma-300m');
  });
}
