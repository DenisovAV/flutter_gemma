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

# === POST_BUILD: Copy files to bundle ===
# Linux bundle structure: bundle/data/, bundle/lib/

set(BUNDLE_DIR "${CMAKE_BINARY_DIR}/bundle")

# Copy JAR to data directory
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/data"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${SETUP_OUTPUT_DIR}/data/litertlm-server.jar"
    "${BUNDLE_DIR}/data/litertlm-server.jar"
  COMMENT "Copying litertlm-server.jar to bundle/data/..."
)

# Copy JRE to lib/jre (only if not exists)
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/lib"
  COMMAND bash -c "if [ ! -f '${BUNDLE_DIR}/lib/jre/bin/java' ]; then echo 'Copying JRE...'; cp -r '${SETUP_OUTPUT_DIR}/jre' '${BUNDLE_DIR}/lib/jre'; else echo 'JRE already exists, skipping'; fi"
  COMMENT "Checking/copying JRE to bundle/lib/jre/..."
)

# Copy native libraries to lib/litertlm (only if not exists)
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/lib/litertlm"
  COMMAND bash -c "if [ ! -f '${BUNDLE_DIR}/lib/litertlm/liblitertlm_jni.so' ]; then echo 'Copying natives...'; cp '${SETUP_OUTPUT_DIR}/litertlm/'* '${BUNDLE_DIR}/lib/litertlm/' 2>/dev/null || true; else echo 'Natives already exist, skipping'; fi"
  COMMENT "Checking/copying native libraries to bundle/lib/litertlm/..."
)
