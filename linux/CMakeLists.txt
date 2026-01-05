# Flutter Gemma Linux Plugin
#
# This CMakeLists.txt sets up the Linux plugin and runs a bash script
# to download JRE, copy JAR, and extract native libraries during build.

cmake_minimum_required(VERSION 3.14)

project(flutter_gemma LANGUAGES CXX)

# This value is used when generating builds using this plugin
set(PLUGIN_NAME "flutter_gemma_plugin")

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "flutter_gemma_plugin.cc"
)

# Apply standard settings
apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# Empty bundled libraries (we copy manually via POST_BUILD)
set(flutter_gemma_bundled_libraries "" PARENT_SCOPE)

# === LiteRT-LM Desktop Setup ===
set(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(SETUP_SCRIPT "${PLUGIN_DIR}/scripts/setup_desktop.sh")
set(SETUP_OUTPUT_DIR "${CMAKE_BINARY_DIR}/flutter_gemma_resources")

# Custom target to run setup script
add_custom_target(flutter_gemma_setup ALL
  COMMAND bash "${SETUP_SCRIPT}" "${PLUGIN_DIR}" "${SETUP_OUTPUT_DIR}"
  WORKING_DIRECTORY "${PLUGIN_DIR}"
  COMMENT "Setting up LiteRT-LM Desktop (JRE, JAR, natives)..."
  VERBATIM
)

add_dependencies(${PLUGIN_NAME} flutter_gemma_setup)

# === Install: Copy files to bundle ===
# Linux bundle structure: bundle/data/, bundle/lib/
# Using install() commands to integrate with Flutter's ninja install

set(BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

# Install JAR to data directory
install(FILES "${SETUP_OUTPUT_DIR}/data/litertlm-server.jar"
  DESTINATION "${BUNDLE_DATA_DIR}"
  OPTIONAL)

# Install JRE to lib/jre
install(DIRECTORY "${SETUP_OUTPUT_DIR}/jre/"
  DESTINATION "${BUNDLE_LIB_DIR}/jre"
  OPTIONAL
  USE_SOURCE_PERMISSIONS)

# Install native libraries to lib/litertlm
install(DIRECTORY "${SETUP_OUTPUT_DIR}/litertlm/"
  DESTINATION "${BUNDLE_LIB_DIR}/litertlm"
  OPTIONAL
  USE_SOURCE_PERMISSIONS)
