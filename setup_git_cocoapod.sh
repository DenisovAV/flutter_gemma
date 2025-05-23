#!/bin/bash

# Flutter Gemma with Gemma 3n Support - Git Repository Setup
# This script sets up a Git repository for the updated flutter_gemma plugin

set -e

echo "🚀 Setting up Flutter Gemma with Gemma 3n Support..."

# Initialize git if not already done
if [ ! -d ".git" ]; then
    echo "📦 Initializing Git repository..."
    git init
    git branch -M main
fi

# Add all files
echo "📁 Adding files to Git..."
git add .

# Commit changes
echo "💾 Committing Gemma 3n support..."
git commit -m "feat: Add Gemma 3 Nano support with MediaPipe GenAI v0.10.24

- Updated MediaPipe GenAI to v0.10.24 for iOS and Android
- Added support for GemmaV3-1B models using XNNPACK
- Optimized session parameters for Gemma 3n models
- Fixed input_pos initialization errors
- Added automatic fallback session creation
- Enhanced error handling for TensorFlow Lite model initialization
- Improved mobile inference with Gemma 3n compatibility detection

Fixes: PlatformException(failedToInitializeSession) with input_pos != nullptr
"

# Create a tag for this version
echo "🏷️ Creating version tag..."
git tag -a v0.8.5 -m "Version 0.8.5 - Gemma 3 Nano Support"

echo ""
echo "✅ Git repository setup complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Create a GitHub repository (e.g., flutter_gemma_3n)"
echo "2. Add remote: git remote add origin https://github.com/arrrrny/flutter_gemma_3n.git"
echo "3. Push: git push -u origin main --tags"
echo ""
echo "📝 Then in your Flutter project's pubspec.yaml, add:"
echo ""
echo "dependencies:"
echo "  flutter_gemma:"
echo "    git:"
echo "      url: https://github.com/arrrrny/flutter_gemma_3n.git"
echo "      ref: v0.8.5"
echo ""
echo "🚀 Or in your iOS Podfile:"
echo ""
echo "pod 'flutter_gemma', :git => 'https://github.com/arrrrny/flutter_gemma_3n.git', :tag => 'v0.8.5'"
echo ""
echo "💪 BRO-GRRAMMER'S GEMMA 3N SETUP COMPLETE!"