#!/bin/bash
# Build and run TransReaderSwift as a proper .app bundle
# This avoids the "Cannot index window tabs due to missing main bundle identifier" error

set -e

APP_NAME="TransReader"
BUNDLE_ID="com.transreader.swift"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "Building TransReaderSwift..."
swift build

echo "Creating .app bundle..."
mkdir -p "$MACOS_DIR"

# Copy executable
cp "$BUILD_DIR/debug/TransReaderSwift" "$MACOS_DIR/TransReaderSwift"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>TransReaderSwift</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Create entitlements for accessibility
cat > "$BUILD_DIR/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
EOF

echo "Signing .app bundle (ad-hoc)..."
codesign --force --deep --sign - --entitlements "$BUILD_DIR/entitlements.plist" "$APP_DIR"

echo "Launching $APP_NAME..."
open "$APP_DIR"
