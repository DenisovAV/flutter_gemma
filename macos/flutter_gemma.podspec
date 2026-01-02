#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma'
  s.version          = '0.11.14'
  s.summary          = 'Flutter Gemma - Run Gemma AI models locally on desktop'
  s.description      = <<-DESC
Flutter plugin for running Gemma AI models locally on macOS using LiteRT-LM.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sasha Denisov' => 'denisov.shureg@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  # Resources - JAR file for LiteRT-LM server
  s.resources        = ['Resources/**/*']

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Script to setup JRE and JAR before build
  s.script_phase = {
    :name => 'Setup LiteRT-LM Desktop',
    :script => 'sh "${PODS_TARGET_SRCROOT}/scripts/setup_desktop.sh" "${PODS_TARGET_SRCROOT}" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"',
    :execution_position => :before_compile,
    :shell_path => '/bin/sh'
  }
end
