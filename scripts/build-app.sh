#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Container Desktop"
EXECUTABLE_NAME="ContainerDesktop"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Assets/container-desktop-app-icon-v3.png"
ICONSET_DIR="$ROOT_DIR/.build/ContainerDesktop.iconset"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.containerdesktop.app}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "Building release executable…"
swift build --package-path "$ROOT_DIR" -c release
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"

echo "Creating ${APP_PATH}…"
rm -rf "$APP_PATH" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"

make_icon() {
    local filename="$1"
    local size="$2"
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$filename" >/dev/null
}

echo "Generating application icon…"
make_icon icon_16x16.png 16
make_icon icon_16x16@2x.png 32
make_icon icon_32x32.png 32
make_icon icon_32x32@2x.png 64
make_icon icon_128x128.png 128
make_icon icon_128x128@2x.png 256
make_icon icon_256x256.png 256
make_icon icon_256x256@2x.png 512
make_icon icon_512x512.png 512
make_icon icon_512x512@2x.png 1024
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "Signing application…"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - \
        --entitlements "$ROOT_DIR/Packaging/ContainerDesktop.entitlements" \
        "$APP_PATH"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        --entitlements "$ROOT_DIR/Packaging/ContainerDesktop.entitlements" \
        "$APP_PATH"
fi

codesign --verify --deep --strict "$APP_PATH"
echo "Done: $APP_PATH"
