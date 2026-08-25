#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/issoeocio/Projects/DeepResearch"
APP_BUNDLE="/Applications/DeepResearch.app"

echo "🔨 Building DeepResearch Swift project..."

# 1. Build the Swift project
cd "$PROJECT_DIR"
swift build 2>&1

# 2. Copy the built executable to the app bundle
BINARY_SOURCE="$PROJECT_DIR/.build/debug/DeepResearch"
BINARY_DESTINATION="$APP_BUNDLE/Contents/MacOS/DeepResearch"

if [ -f "$BINARY_SOURCE" ]; then
    cp -f "$BINARY_SOURCE" "$BINARY_DESTINATION"
    chmod +x "$BINARY_DESTINATION"
    echo "✅ Updated $BINARY_DESTINATION"
else
    echo "⚠️  Binary not found at $BINARY_SOURCE — skipping copy"
fi

# 3. Verify the app bundle structure
if [ -d "$APP_BUNDLE/Contents/MacOS" ] && [ -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo "✅ App bundle structure verified at $APP_BUNDLE"
else
    echo "❌ App bundle structure incomplete"
    exit 1
fi

echo "🏁 Build complete! DeepResearch.app should now reflect the latest changes."
echo "   To launch: open /Applications/DeepResearch.app"