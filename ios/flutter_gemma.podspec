#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma'
  s.version          = '0.14.0'
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

  # LiteRT-LM gpu_registry calls SharedLibrary::Load by basename (e.g.
  # "libLiteRtMetalAccelerator.dylib") at runtime. Native Assets ships these
  # as *.framework/<binary>, but iOS dyld 4 doesn't auto-fallback by basename
  # the way macOS does. We add lib*.dylib symlinks alongside the bundled
  # frameworks so dlopen resolves at runtime — without this, Metal GPU
  # delegate fails to load and the model silently runs on CPU.
  s.script_phase = {
    :name => 'Setup LiteRT-LM iOS',
    :execution_position => :after_compile,
    :script => <<~SHELL
      set -e
      FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Frameworks"
      [ -d "${FRAMEWORKS}" ] || exit 0
      for base in LiteRtMetalAccelerator GemmaModelConstraintProvider; do
        src="${base}.framework/${base}"
        dst="${FRAMEWORKS}/lib${base}.dylib"
        if [ -e "${FRAMEWORKS}/${src}" ] && [ ! -e "${dst}" ]; then
          ln -sf "${src}" "${dst}"
          echo "[flutter_gemma] symlinked lib${base}.dylib -> ${src}"
        fi
      done
    SHELL
  }
end
