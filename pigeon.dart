import 'package:pigeon/pigeon.dart';
// Command to generate pigeon files: dart run pigeon --input pigeon.dart

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/pigeon.g.dart',
  kotlinOut:
      'android/src/main/kotlin/dev/flutterberlin/flutter_gemma/PigeonInterface.g.kt',
  kotlinOptions: KotlinOptions(package: 'dev.flutterberlin.flutter_gemma'),
  swiftOut: 'ios/Classes/PigeonInterface.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'flutter_gemma',
))
@HostApi()
abstract class PlatformService {
  @async
  void createModel({
    required int maxTokens,
    required String modelPath,
    required List<int>? loraRanks,
    required int int,
  });

  @async
  void closeModel();

  @async
  void createSession({
    required double temperature,
    required int randomSeed,
    required String? loraPath,
    required int topK,
  });

  @async
  void closeSession();

  @async
  int sizeInTokens(String prompt);

  @async
  void addQueryChunk(String prompt);

  @async
  String generateResponse();

  @async
  void generateResponseAsync();
}
