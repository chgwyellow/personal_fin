#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FinTrack"
PRODUCT_NAME="PersonalFinanceApp"
VERSION="${1:-0.1.3}"
BUILD_NUMBER="${BUILD_NUMBER:-${VERSION//./}}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ARCHS_VALUE="${ARCHS:-arm64}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$ROOT_DIR/releases/$APP_NAME-$VERSION"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RESOURCE_DIR="$APP_DIR/Contents/Resources"

rm -rf "$RELEASE_DIR"
mkdir -p "$BIN_DIR" "$RESOURCE_DIR"

build_arch() {
    local arch="$1"
    swift build -c release --arch "$arch" --product "$PRODUCT_NAME"
}

if [[ "$ARCHS_VALUE" == "arm64,x86_64" || "$ARCHS_VALUE" == "x86_64,arm64" ]]; then
    build_arch arm64
    build_arch x86_64
    lipo -create \
        "$BUILD_DIR/arm64-apple-macosx/release/$PRODUCT_NAME" \
        "$BUILD_DIR/x86_64-apple-macosx/release/$PRODUCT_NAME" \
        -output "$BIN_DIR/$PRODUCT_NAME"
else
    build_arch "$ARCHS_VALUE"
    cp "$BUILD_DIR/${ARCHS_VALUE}-apple-macosx/release/$PRODUCT_NAME" "$BIN_DIR/$PRODUCT_NAME"
fi

cp Resources/FinTrack-Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/FinTrack.icns "$RESOURCE_DIR/FinTrack.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
chmod +x "$BIN_DIR/$PRODUCT_NAME"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "Warning: SIGNING_IDENTITY is not set; package is unsigned." >&2
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" \
    "$RELEASE_DIR/$APP_NAME-$VERSION.zip"
shasum -a 256 "$RELEASE_DIR/$APP_NAME-$VERSION.zip" \
    | tee "$RELEASE_DIR/$APP_NAME-$VERSION.zip.sha256"

echo "Created: $RELEASE_DIR"
