import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';

import 'ai_service.dart';

// Pass at build time: flutter run --dart-define=GEMINI_API_KEY=AIza...
const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

class CloudAIService implements AIService {
  Genkit? _ai;

  @override
  Future<void> initialize() async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'GEMINI_API_KEY is not set. '
        'Run with --dart-define=GEMINI_API_KEY=your_key',
      );
    }
    _ai = Genkit(plugins: [googleAI(apiKey: _apiKey)]);
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final ai = _ai;
    if (ai == null) throw StateError('CloudAIService not initialized');

    final stream = ai.generateStream(
      model: googleAI.gemini('gemini-3.7-flash'),
      prompt: prompt,
    );

    await for (final chunk in stream) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<void> dispose() async {
    _ai = null;
  }
}
