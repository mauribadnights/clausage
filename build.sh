#!/bin/bash
set -e

APP_NAME="Clausage"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
ASSETS_DIR="$APP_NAME/Resources/Assets.xcassets"

echo "Building $APP_NAME..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SPM resource bundle (pricing.json, etc.)
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "Copied resource bundle"
fi

# Copy Info.plist and inject version from latest git tag
cp "$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/"
GIT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
if [ -n "$GIT_VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GIT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
    echo "Version set to $GIT_VERSION (from git tag)"
fi

# Compile asset catalog (app icon)
if [ -d "$ASSETS_DIR" ]; then
    echo "Compiling asset catalog..."
    actool "$ASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/clausage-assets-info.plist \
        2>/dev/null || echo "Warning: actool failed, falling back to manual icon copy"

    # If actool didn't produce the .icns, fall back to iconutil
    if [ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
        echo "Using iconutil fallback..."
        ICONSET_DIR="/tmp/AppIcon.iconset"
        rm -rf "$ICONSET_DIR"
        mkdir -p "$ICONSET_DIR"
        APPICONSET="$ASSETS_DIR/AppIcon.appiconset"
        cp "$APPICONSET/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
        cp "$APPICONSET/icon_16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
        cp "$APPICONSET/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
        cp "$APPICONSET/icon_32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
        cp "$APPICONSET/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
        cp "$APPICONSET/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
        cp "$APPICONSET/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
        cp "$APPICONSET/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
        cp "$APPICONSET/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
        cp "$APPICONSET/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        rm -rf "$ICONSET_DIR"
    fi
fi

echo "Done! Run with: open $APP_BUNDLE"
