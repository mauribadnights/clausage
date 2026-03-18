#!/bin/bash
set -e

APP_NAME="Clausage"
APP_BUNDLE="$APP_NAME-Debug.app"
BUILD_DIR=".build/debug"

echo "Building $APP_NAME (debug)..."
swift build

echo "Creating debug app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/"

# Compile asset catalog
ASSETS_DIR="$APP_NAME/Resources/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    actool "$ASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/clausage-debug-assets.plist \
        2>/dev/null || true
fi

echo "Done! Launching debug build..."
open "$APP_BUNDLE"
