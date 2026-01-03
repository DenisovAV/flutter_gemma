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
target_include_directories(${PLUGIN_NAME} PUBLIC
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
set(SETUP_OUTPUT_DIR "${CMAKE_BINARY_DIR}/flutter_gemma_resources")

# Custom target to run setup script
add_custom_target(flutter_gemma_setup ALL
  COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${SETUP_SCRIPT}" -PluginDir "${PLUGIN_DIR}" -OutputDir "${SETUP_OUTPUT_DIR}"
  WORKING_DIRECTORY "${PLUGIN_DIR}"
  COMMENT "Setting up LiteRT-LM Desktop (JRE, JAR, natives)..."
  VERBATIM
)

# Ensure setup runs before plugin builds
add_dependencies(${PLUGIN_NAME} flutter_gemma_setup)

# === POST_BUILD: Copy files to runner directory for Debug builds ===
# This ensures files are available when running `flutter run` (Debug mode)

# Get the runner output directory (where the .exe will be)
# CMAKE_RUNTIME_OUTPUT_DIRECTORY is set by Flutter to the runner directory
if(DEFINED CMAKE_RUNTIME_OUTPUT_DIRECTORY)
  set(RUNNER_DIR "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
else()
  # Fallback: go up from plugin build dir to runner
  get_filename_component(RUNNER_DIR "${CMAKE_BINARY_DIR}/../../runner/${CMAKE_BUILD_TYPE}" ABSOLUTE)
endif()

message(STATUS "flutter_gemma: Runner directory: ${RUNNER_DIR}")
message(STATUS "flutter_gemma: Setup output: ${SETUP_OUTPUT_DIR}")

# POST_BUILD: Copy JAR to runner's data directory
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${RUNNER_DIR}/data"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${SETUP_OUTPUT_DIR}/data/litertlm-server.jar"
    "${RUNNER_DIR}/data/litertlm-server.jar"
  COMMENT "Copying litertlm-server.jar to runner..."
  VERBATIM
)

# POST_BUILD: Copy JRE to runner directory
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${SETUP_OUTPUT_DIR}/jre"
    "${RUNNER_DIR}/jre"
  COMMENT "Copying JRE to runner..."
  VERBATIM
)

# POST_BUILD: Copy native libraries (if any exist)
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${RUNNER_DIR}/litertlm"
  COMMAND ${CMAKE_COMMAND} -E copy_directory
    "${SETUP_OUTPUT_DIR}/litertlm"
    "${RUNNER_DIR}/litertlm"
  COMMENT "Copying native libraries to runner..."
  VERBATIM
)

# === Install rules for Release builds ===
if(DEFINED INSTALL_BUNDLE_DATA_DIR AND NOT "${INSTALL_BUNDLE_DATA_DIR}" STREQUAL "")
  # Install JAR to data directory
  install(FILES "${SETUP_OUTPUT_DIR}/data/litertlm-server.jar"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    OPTIONAL
  )
endif()

if(DEFINED CMAKE_INSTALL_PREFIX AND NOT "${CMAKE_INSTALL_PREFIX}" STREQUAL "")
  # Install JRE to jre directory (next to executable)
  install(DIRECTORY "${SETUP_OUTPUT_DIR}/jre/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/jre"
    OPTIONAL
    USE_SOURCE_PERMISSIONS
  )

  # Install native libraries to litertlm directory
  install(DIRECTORY "${SETUP_OUTPUT_DIR}/litertlm/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/litertlm"
    OPTIONAL
  )
endif()
