// ignore_for_file: unused_import
import 'package:genkit_hybrid/genkit_hybrid.dart';

/// Minimal illustration. `onDeviceModel` and `cloudModel` are ordinary Genkit
/// Models provided by the host app (e.g. from genkit_flutter_gemma and googleAI).
void buildHybrid(/* Model onDeviceModel, Model cloudModel */) {
  // Prefer on-device, fall back to cloud on failure/offline:
  // final smart = hybridModelOnDeviceCloud(
  //   onDevice: onDeviceModel,
  //   cloud: cloudModel,
  //   strategy: FallbackStrategy([kOnDevice, kCloud]),
  // );
}
