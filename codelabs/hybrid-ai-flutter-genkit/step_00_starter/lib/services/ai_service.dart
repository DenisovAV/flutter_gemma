abstract class AIService {
  Future<void> initialize();
  Stream<String> generateResponseStream(String prompt);
  Future<void> dispose();
}
