import 'package:pigeon/pigeon.dart';
// Command to generate: dart run pigeon --input pigeon.dart

/// Availability of the OS built-in model. Wire order is frozen — append only.
enum AvailabilityStatus {
  available,
  downloadable,
  downloading,
  unavailableDeviceUnsupported,
  unavailableOsTooOld,
  unavailableDisabled, // Apple Intelligence off in Settings
  unavailableOther,
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/pigeon.g.dart',
  kotlinOut:
      'android/src/main/kotlin/dev/flutterberlin/flutter_gemma_builtin_ai/PigeonInterface.g.kt',
  kotlinOptions:
      KotlinOptions(package: 'dev.flutterberlin.flutter_gemma_builtin_ai'),
  swiftOut: 'darwin/Classes/PigeonInterface.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'flutter_gemma_builtin_ai',
))
@HostApi()
abstract class BuiltInAiService {
  @async
  AvailabilityStatus checkAvailability();

  /// Starts the OS feature download (AICore). Progress arrives on the event
  /// channel as {code: DOWNLOAD_PROGRESS, bytesDownloaded, bytesTotal}.
  /// No-op on darwin (returns immediately; readiness is user-controlled).
  @async
  void downloadFeature();

  @async
  void createModel({required bool supportImage});

  @async
  void closeModel();

  @async
  void createSession({
    required int sessionId,
    required double temperature,
    required int topK,
    double? topP,
    int? maxOutputTokens,
    String? systemInstruction,
  });

  @async
  void closeSession(int sessionId);

  @async
  void addQueryChunk({required int sessionId, required String text});

  @async
  void addImage({required int sessionId, required Uint8List imageBytes});

  @async
  String generateResponse(int sessionId);

  @async
  void generateResponseAsync(int sessionId);

  @async
  void stopGeneration(int sessionId);

  @async
  int countTokens(String text);
}
