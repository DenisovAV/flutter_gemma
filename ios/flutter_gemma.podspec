#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma'
  s.version          = '0.14.5'
  s.summary          = 'Flutter plugin for running Gemma AI models locally with Gemma 3 Nano support.'
  s.description      = <<-DESC
The plugin allows running the Gemma AI model locally on a device from a Flutter application.
Includes support for Gemma 3 Nano models with optimized MediaPipe GenAI v0.10.33.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Flutter Berlin' => 'flutter@flutterberlin.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/*.swift'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksGenAI', '= 0.10.33'
  s.dependency 'MediaPipeTasksGenAIC', '= 0.10.33'
  s.dependency 'TensorFlowLiteC', '0.0.1-nightly.20250619'
  s.platform = :ios, '16.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }
  s.swift_version = '5.0'

  # No script_phase needed: the upstream LiteRT-LM dlopen path is patched in
  # native/litert_lm/patch_c_api.sh (FLUTTER_GEMMA_GPU_REGISTRY_PATCH) to load
  # accelerator frameworks via their @executable_path-relative .framework path,
  # so the host app's Frameworks/ stays App-Store-clean (no rogue dylibs that
  # would trigger ITMS-90432, see #245).
end
