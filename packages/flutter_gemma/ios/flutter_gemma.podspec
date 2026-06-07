#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma'
  s.version          = '0.16.3'
  s.summary          = 'Flutter plugin for running Gemma and other LLMs locally on iOS.'
  s.description      = <<-DESC
Core runtime for running Gemma 4, Gemma3n, Gemma 3, FastVLM, Qwen3,
Qwen 2.5, DeepSeek R1, Phi-4, FunctionGemma, and SmolLM locally on iOS.
Inference engines are opt-in packages: `flutter_gemma_mediapipe`
(`.task`, MediaPipe GenAI) and `flutter_gemma_litertlm` (`.litertlm`).
Supports multimodal vision + audio, function calling, thinking mode,
text embeddings, and on-device RAG.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Flutter Berlin' => 'flutter@flutterberlin.dev' }
  s.source           = { :path => '.' }
  # Sources live under the SPM layout (flutter_gemma/Sources/flutter_gemma/);
  # the companion Package.swift gives SPM consumers the same sources.
  s.source_files = 'flutter_gemma/Sources/flutter_gemma/**/*.swift'
  s.dependency 'Flutter'
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
