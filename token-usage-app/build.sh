#!/bin/bash
# Build TokenUsageApp into a .app bundle using swiftc directly.
# Usage: ./build.sh [run]

set -euo pipefail

APP_NAME="TokenUsageApp"
BUNDLE="$APP_NAME.app"
SRC_DIR="Sources/TokenUsageApp"
BUILD_DIR=".build"
BINARY="$BUILD_DIR/$APP_NAME"
SDK=$(xcrun --show-sdk-path)
MIN_OS="14.0"
ARCH="${ARCH:-arm64}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/../VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  echo "VERSION file not found at $VERSION_FILE" >&2
  exit 1
fi
APP_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

# Collect all Swift sources
SOURCES=$(find "$SRC_DIR" -name "*.swift" | sort)

echo "→ Compiling $APP_NAME ($ARCH)..."
mkdir -p "$BUILD_DIR"

swiftc \
  -sdk "$SDK" \
  -target "${ARCH}-apple-macosx$MIN_OS" \
  -framework SwiftUI \
  -framework Charts \
  -framework ServiceManagement \
  -parse-as-library \
  $SOURCES \
  -o "$BINARY"

echo "→ Building app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TokenUsageApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.lampham.tokenusage</string>
    <key>CFBundleName</key>
    <string>Token Usage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "✓ Built $BUNDLE"

if [[ "${1:-}" == "run" ]]; then
  echo "→ Launching..."
  open "$BUNDLE"
fi
