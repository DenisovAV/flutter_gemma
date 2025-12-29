#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma'
  s.version          = '0.11.15'
  s.summary          = 'Flutter plugin for running Gemma AI models locally with Gemma 3 Nano support.'
  s.description      = <<-DESC
The plugin allows running the Gemma AI model locally on a device from a Flutter application.
Includes support for Gemma 3 Nano models with optimized MediaPipe GenAI v0.10.24.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Flutter Berlin' => 'flutter@flutterberlin.dev' }
  s.source           = { :path => '.' }
  # Source files - Swift/ObjC and SentencePiece C++ (.cc only!)
  # CRITICAL: Don't include .h from sentencepiece - they will be found via HEADER_SEARCH_PATHS
  # Including them causes Swift to try to compile C++ headers
  s.source_files = [
    'Classes/*.{h,m,mm,swift}',
    'Classes/sentencepiece/src/*.cc',
    'Classes/sentencepiece/src/builtin_pb/*.cc',
    'Classes/sentencepiece/third_party/protobuf-lite/*.cc',
    'Classes/sentencepiece/third_party/protobuf-lite/google/protobuf/*.cc',
    'Classes/sentencepiece/third_party/protobuf-lite/google/protobuf/stubs/*.cc',
    'Classes/sentencepiece/third_party/protobuf-lite/google/protobuf/io/*.cc',
    'Classes/sentencepiece/third_party/absl/**/*.cc',
    'Classes/sentencepiece/third_party/darts_clone/**/*.cc',
    'Classes/sentencepiece/third_party/esaxx/**/*.cc'
  ]

  # Exclude test files and trainer (not needed for inference)
  s.exclude_files = [
    'Classes/sentencepiece/src/*_test.cc',
    'Classes/sentencepiece/src/testharness.cc',
    'Classes/sentencepiece/src/trainer*.cc',
    'Classes/sentencepiece/src/*_trainer.cc',
    'Classes/sentencepiece/src/spm_*.cc'
  ]

  # Public header is only our ObjC wrapper
  s.public_header_files = 'Classes/SentencePieceWrapper.h'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksGenAI', '= 0.10.24'
  s.dependency 'MediaPipeTasksGenAIC', '= 0.10.24'
  s.dependency 'TensorFlowLiteC', '0.0.1-nightly.20250619'
  s.dependency 'TensorFlowLiteSwift', '0.0.1-nightly.20250619'
  s.dependency 'TensorFlowLiteSelectTfOps', '0.0.1-nightly.20250619'
  s.platform = :ios, '16.0'

  # C++ library linkage
  s.library = 'c++'

  # Custom module map that only exposes ObjC headers
  s.module_map = 'Classes/module.modulemap'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # Rename protobuf namespace to avoid conflict with MediaPipe's protobuf
    # SPM_PROTOBUF_NAMESPACE renames google::protobuf to google::protobuf_sp
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_PTHREAD=1 GOOGLE_PROTOBUF_NO_RTTI=1 protobuf=protobuf_sentencepiece',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Classes/sentencepiece" "${PODS_TARGET_SRCROOT}/Classes/sentencepiece/src" "${PODS_TARGET_SRCROOT}/Classes/sentencepiece/src/builtin_pb" "${PODS_TARGET_SRCROOT}/Classes/sentencepiece/third_party/protobuf-lite" "${PODS_TARGET_SRCROOT}/Classes/sentencepiece/third_party"',
    'OTHER_CPLUSPLUSFLAGS' => '-fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections',
    # Conditional force_load: only for device builds (TensorFlowLiteSelectTfOps doesn't have simulator slice)
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '-force_load $(SRCROOT)/Pods/TensorFlowLiteSelectTfOps/Frameworks/TensorFlowLiteSelectTfOps.xcframework/ios-arm64/TensorFlowLiteSelectTfOps.framework/TensorFlowLiteSelectTfOps -lc++',
    # Don't force_load on simulator (TensorFlowLiteSelectTfOps.xcframework only contains ios-arm64 slice)
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '-lc++'
  }
  s.swift_version = '5.0'
end
