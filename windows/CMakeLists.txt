# Flutter Gemma Windows Plugin
#
# Minimal plugin setup for the FFI path. Native libraries (LiteRtLm.dll,
# LiteRt.dll, LiteRtWebGpuAccelerator.dll, companions, StreamProxy.dll) are
# bundled via hook/build.dart (Native Assets) which downloads them at build
# time and places them next to the executable in the Flutter runner directory.

cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter_gemma")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin — do not change.
set(PLUGIN_NAME "flutter_gemma_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_gemma_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Native asset DLLs are handled by hook/build.dart + Native Assets; nothing to
# bundle via CMake here.
set(flutter_gemma_bundled_libraries
  ""
  PARENT_SCOPE
)
