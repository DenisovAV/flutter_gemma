#!/bin/bash
# Bundle LiteRT-LM server into macOS Flutter app
#
# Usage: ./scripts/bundle_macos.sh <flutter_app_path>
#
# This script copies the JAR and native libraries to the Flutter app's
# macOS Resources folder for bundling into the app.
#
# The files will be included in:
#   MyApp.app/Contents/Resources/litertlm-server.jar
#   MyApp.app/Contents/Frameworks/litertlm/macos/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <flutter_app_path>"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/my_flutter_app"
    exit 1
fi

FLUTTER_APP="$1"
MACOS_DIR="$FLUTTER_APP/macos"

if [ ! -d "$MACOS_DIR" ]; then
    echo "❌ macOS folder not found at: $MACOS_DIR"
    echo "   Run 'flutter create --platforms=macos .' in your Flutter app first"
    exit 1
fi

echo "🍎 Bundling LiteRT-LM for macOS..."
echo "   Flutter app: $FLUTTER_APP"

# Build server JAR if not exists
JAR_PATH="$PROJECT_DIR/build/libs/litertlm-server-0.1.0-all.jar"
if [ ! -f "$JAR_PATH" ]; then
    echo "📦 Building server JAR..."
    "$SCRIPT_DIR/build.sh"
fi

# Setup natives if not exists
NATIVES_PATH="$PROJECT_DIR/natives/macos"
if [ ! -d "$NATIVES_PATH" ] || [ -z "$(ls -A "$NATIVES_PATH" 2>/dev/null)" ]; then
    echo "📥 Setting up native libraries..."
    "$SCRIPT_DIR/setup_natives.sh" macos
fi

# Create destination directories in Flutter app
RESOURCES_DIR="$MACOS_DIR/Runner/Resources"
FRAMEWORKS_DIR="$MACOS_DIR/Runner/Frameworks/litertlm/macos"

mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy JAR to Resources
echo "📋 Copying server JAR..."
cp "$JAR_PATH" "$RESOURCES_DIR/litertlm-server.jar"
echo "   → $RESOURCES_DIR/litertlm-server.jar"

# Copy natives to Frameworks
echo "📋 Copying native libraries..."
if [ -d "$NATIVES_PATH" ] && [ -n "$(ls -A "$NATIVES_PATH" 2>/dev/null)" ]; then
    cp -r "$NATIVES_PATH"/* "$FRAMEWORKS_DIR/"
    echo "   → $FRAMEWORKS_DIR/"
    ls -la "$FRAMEWORKS_DIR"
else
    echo "⚠️  No native libraries found. App will use CPU backend."
fi

# Create Xcode build phase script
BUILD_PHASE_SCRIPT="$MACOS_DIR/Runner/copy_litertlm.sh"
cat > "$BUILD_PHASE_SCRIPT" << 'EOF'
#!/bin/bash
# Xcode Build Phase: Copy LiteRT-LM resources
# Add this as a "Run Script" build phase in Xcode

RESOURCES_SRC="${PROJECT_DIR}/Runner/Resources"
FRAMEWORKS_SRC="${PROJECT_DIR}/Runner/Frameworks/litertlm"
RESOURCES_DST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources"
FRAMEWORKS_DST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Frameworks/litertlm"

# Copy JAR
if [ -f "${RESOURCES_SRC}/litertlm-server.jar" ]; then
    mkdir -p "${RESOURCES_DST}"
    cp "${RESOURCES_SRC}/litertlm-server.jar" "${RESOURCES_DST}/"
    echo "Copied litertlm-server.jar to Resources"
fi

# Copy natives
if [ -d "${FRAMEWORKS_SRC}" ]; then
    mkdir -p "${FRAMEWORKS_DST}"
    cp -r "${FRAMEWORKS_SRC}"/* "${FRAMEWORKS_DST}/"
    echo "Copied LiteRT-LM natives to Frameworks"
fi
EOF
chmod +x "$BUILD_PHASE_SCRIPT"

echo ""
echo "✅ Bundling complete!"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Open Xcode project:"
echo "   open $MACOS_DIR/Runner.xcworkspace"
echo ""
echo "2. Add 'Run Script' build phase:"
echo "   - Select Runner target"
echo "   - Build Phases → + → New Run Script Phase"
echo "   - Paste: \"\${PROJECT_DIR}/Runner/copy_litertlm.sh\""
echo ""
echo "3. Build and run your Flutter app:"
echo "   flutter run -d macos"
