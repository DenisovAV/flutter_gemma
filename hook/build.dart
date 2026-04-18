import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

/// Resolve prebuilt directory name for the given OS + architecture.
/// iOS distinguishes device vs simulator via IOSSdk.
String _prebuiltDirName(OS os, Architecture arch, {IOSSdk? iOSSdk}) {
  if (os == OS.iOS) {
    if (iOSSdk == IOSSdk.iPhoneSimulator) {
      // Simulator on Apple Silicon is arm64, on Intel is x86_64.
      // We only ship arm64 simulator builds.
      return 'ios_sim_arm64';
    }
    return 'ios_arm64';
  }
  final osName = switch (os) {
    OS.macOS => 'macos',
    OS.linux => 'linux',
    OS.windows => 'windows',
    _ => throw UnsupportedError('Unsupported OS: $os'),
  };
  return '${osName}_${_archName(arch)}';
}

String _archName(Architecture arch) => switch (arch) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError('Unsupported arch: $arch'),
    };

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Supported platforms: desktop + iOS
    // Android uses JNI engine, Web uses MediaPipe JS
    if (os != OS.macOS && os != OS.linux && os != OS.windows && os != OS.iOS) {
      return;
    }

    final arch = codeConfig.targetArchitecture;
    final iOSSdk = os == OS.iOS ? codeConfig.iOS.targetSdk : null;
    final dirName = _prebuiltDirName(os, arch, iOSSdk: iOSSdk);
    final prebuiltDir =
        input.packageRoot.resolve('native/litert_lm/prebuilt/$dirName/');

    final mainFileName = os.dylibFileName(_mainLibName);
    final mainFileUri = prebuiltDir.resolve(mainFileName);
    if (!File.fromUri(mainFileUri).existsSync()) {
      throw Exception('Main library not found: $mainFileUri');
    }

    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: 'src/native/$_mainLibName',
        linkMode: DynamicLoadingBundled(),
        file: mainFileUri,
      ),
    );

    // Stream proxy — tiny C lib that copies callback strings to heap
    final proxyFileName = os.dylibFileName('StreamProxy');
    final proxyFileUri = prebuiltDir.resolve(proxyFileName);
    if (File.fromUri(proxyFileUri).existsSync()) {
      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: 'src/native/StreamProxy',
          linkMode: DynamicLoadingBundled(),
          file: proxyFileUri,
        ),
      );
    }

    // Companion lib: GemmaModelConstraintProvider (loaded by libLiteRtLm via dlopen)
    final companionFileName = os.dylibFileName('GemmaModelConstraintProvider');
    final companionFileUri = prebuiltDir.resolve(companionFileName);
    if (File.fromUri(companionFileUri).existsSync()) {
      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: 'src/native/GemmaModelConstraintProvider',
          linkMode: DynamicLoadingBundled(),
          file: companionFileUri,
        ),
      );
    }

    output.dependencies.add(prebuiltDir);
  });
}
