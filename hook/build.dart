import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

String _prebuiltDirName(OS os, Architecture arch) {
  final osName = switch (os) {
    OS.macOS => 'macos',
    OS.linux => 'linux',
    OS.windows => 'windows',
    _ => throw UnsupportedError('Unsupported OS: $os'),
  };
  final archName = switch (arch) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => throw UnsupportedError('Unsupported arch: $arch'),
  };
  return '${osName}_$archName';
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    if (os != OS.macOS && os != OS.linux && os != OS.windows) return;

    final arch = codeConfig.targetArchitecture;
    final dirName = _prebuiltDirName(os, arch);
    final prebuiltDir =
        input.packageRoot.resolve('native/litert_lm/prebuilt/$dirName/');

    final mainFileName = os.dylibFileName(_mainLibName);
    final mainFileUri = prebuiltDir.resolve(mainFileName);
    if (!File.fromUri(mainFileUri).existsSync()) {
      throw Exception('Main library not found: $mainFileUri');
    }

    // Only the main C API library is a CodeAsset.
    // Companion libs (accelerators, constraint provider) are copied
    // by platform build scripts to preserve their original filenames
    // (Dart SDK renames dylibs inside frameworks, breaking dlopen).
    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: 'src/native/$_mainLibName',
        linkMode: DynamicLoadingBundled(),
        file: mainFileUri,
      ),
    );

    // Stream proxy — tiny C lib that copies callback strings to heap
    // so NativeCallable.listener receives valid pointers
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

    output.dependencies.add(prebuiltDir);
  });
}
