#!/bin/bash
# Build LiteRT-LM gRPC Server fat JAR
#
# Usage: ./scripts/build.sh
#
# Output: build/libs/litertlm-server-0.1.0-all.jar

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "🔨 Building LiteRT-LM gRPC Server..."

# Check for Gradle wrapper
if [ ! -f "./gradlew" ]; then
    echo "⚠️  Gradle wrapper not found. Initializing..."
    if command -v gradle &> /dev/null; then
        if ! gradle wrapper --gradle-version 8.5; then
            echo "❌ Failed to initialize Gradle wrapper"
            echo "   Check network connection and disk space"
            exit 1
        fi
    else
        echo "❌ Gradle not installed. Please install Gradle 8.5+ first:"
        echo "   brew install gradle"
        exit 1
    fi
fi

# Make gradlew executable
chmod +x ./gradlew

# Build fat JAR
echo "📦 Building fat JAR..."
./gradlew fatJar --no-daemon

# Check output
JAR_PATH="build/libs/litertlm-server-0.1.0-all.jar"
if [ -f "$JAR_PATH" ]; then
    JAR_SIZE=$(du -h "$JAR_PATH" | cut -f1)
    echo "✅ Build successful!"
    echo "   Output: $JAR_PATH ($JAR_SIZE)"
else
    echo "❌ Build failed - JAR not found"
    exit 1
fi
