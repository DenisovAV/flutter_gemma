# Flutter Gemma Windows Plugin
#
# This CMakeLists.txt sets up the Windows plugin and runs a PowerShell script
# to download JRE, copy JAR, and extract native libraries during build.

cmake_minimum_required(VERSION 3.14)

# Project name
set(PROJECT_NAME "flutter_gemma")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_gemma_plugin")

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "flutter_gemma_plugin.cpp"
)

# Apply standard settings for Windows plugins
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Link against Flutter library
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_gemma_bundled_libraries
  ""
  PARENT_SCOPE
)

# === LiteRT-LM Desktop Setup ===
# Run PowerShell script to download JRE, copy JAR, and extract natives

# Get paths
set(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(SETUP_SCRIPT "${PLUGIN_DIR}/scripts/setup_desktop.ps1")

# Custom target to run setup script
add_custom_target(flutter_gemma_setup ALL
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${SETUP_SCRIPT}" -PluginDir "${PLUGIN_DIR}" -OutputDir "${CMAKE_BINARY_DIR}"
  WORKING_DIRECTORY "${PLUGIN_DIR}"
  COMMENT "Setting up LiteRT-LM Desktop (JRE, JAR, natives)..."
  VERBATIM
)

# Ensure setup runs before plugin builds
add_dependencies(${PLUGIN_NAME} flutter_gemma_setup)

# Install JAR to data directory
install(FILES "${CMAKE_BINARY_DIR}/litertlm-server.jar"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  OPTIONAL
)

# Install JRE to jre directory (next to executable)
install(DIRECTORY "${CMAKE_BINARY_DIR}/jre/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/jre"
  OPTIONAL
  USE_SOURCE_PERMISSIONS
)

# Install native libraries to litertlm directory
install(DIRECTORY "${CMAKE_BINARY_DIR}/litertlm/"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/litertlm"
  OPTIONAL
)
