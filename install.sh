#!/bin/bash
# Build + install DeepResearch.app
# Notas:
#   - SPM não compila .xcstrings → .strings (requer xcstringstool manual)
#   - Bundle.module accessor procura na raiz do .app, não em Contents/Resources
#   - Ícone: ChatGPT Image.png → .iconset → .icns
set -euo pipefail

APP_NAME="DeepResearch"
BUNDLE_ID="local.issoeocio.DeepResearch"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_PATH="/Applications/${APP_NAME}.app"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="${APP_NAME}_${APP_NAME}.bundle"

cd "$REPO_DIR"

echo "1/7 Build release..."
swift build --skip-update -c release 2>&1 | tail -3

echo "2/7 Matar app anterior..."
kill -9 "$(pgrep -f "${APP_NAME}.app")" 2>/dev/null || true

echo "3/7 Montar .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

# Binário
cp "$BUILD_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"

echo "4/7 Compilar strings + instalar bundle (raiz + Contents/Resources)..."
BUNDLE_SRC="$BUILD_DIR/$BUNDLE_DIR"

# Bundle na raiz do .app (onde Bundle.module accessor procura)
BUNDLE_ROOT="$APP_PATH/$BUNDLE_DIR"
cp -R "$BUNDLE_SRC" "$BUNDLE_ROOT"

# Bundle em Contents/Resources (localização padrão macOS)
BUNDLE_RES="$APP_PATH/Contents/Resources/$BUNDLE_DIR"
cp -R "$BUNDLE_SRC" "$BUNDLE_RES"

# Compilar xcstrings → .strings em ambos
xcrun xcstringstool compile \
  Sources/DeepResearch/Resources/Localizable.xcstrings \
  --output-directory "$BUNDLE_ROOT" \
  --format stringsAndStringsdict

xcrun xcstringstool compile \
  Sources/DeepResearch/Resources/Localizable.xcstrings \
  --output-directory "$BUNDLE_RES" \
  --format stringsAndStringsdict

echo "5/7 Info.plist..."
cat > "$APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.issoeocio.DeepResearch</string>
    <key>CFBundleName</key>
    <string>DeepResearch</string>
    <key>CFBundleDisplayName</key>
    <string>DeepResearch</string>
    <key>CFBundleExecutable</key>
    <string>DeepResearch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>CFBundleIconFile</key>
    <string>DeepResearch.icns</string>
</dict>
</plist>
PLIST

echo "6/7 Ícone..."
ICONSET="$REPO_DIR/DeepResearch.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
SRC="$REPO_DIR/ChatGPT Image.png"
for spec in "16 16 icon_16x16.png" "32 32 icon_16x16@2x.png" "32 32 icon_32x32.png" \
            "64 64 icon_32x32@2x.png" "128 128 icon_128x128.png" "256 256 icon_128x128@2x.png" \
            "256 256 icon_256x256.png" "512 512 icon_256x256@2x.png" "512 512 icon_512x512.png"; do
    read -r w h name <<< "$spec"
    sips -z "$w" "$h" "$SRC" --out "$ICONSET/$name" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/DeepResearch.icns"

echo "7/7 Code sign + cache bust..."
codesign --force --deep --sign - "$APP_PATH" 2>&1
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo ""
echo "✅ $APP_NAME instalado em $APP_PATH"
echo "   Binário: $(ls -lh "$APP_PATH/Contents/MacOS/$APP_NAME" | awk '{print $5}')"
STR_ROOT=$(find "$BUNDLE_ROOT" -name "*.strings" | wc -l | tr -d ' ')
STR_RES=$(find "$BUNDLE_RES" -name "*.strings" | wc -l | tr -d ' ')
echo "   Strings: $STR_ROOT (raiz) + $STR_RES (Resources)"
echo "   Ícone: $(ls "$APP_PATH/Contents/Resources/DeepResearch.icns" 2>/dev/null && echo "✓" || echo "✗")"
codesign --verify "$APP_PATH" 2>&1 && echo "   Assinatura: ✓"
