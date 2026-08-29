#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="TrafficBar"
VERSION="${TRAFFICBAR_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUNDLE_ID="${TRAFFICBAR_BUNDLE_ID:-com.crossng.TrafficBar}"
REPOSITORY="${TRAFFICBAR_GITHUB_REPOSITORY:-}"
PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
BUILD_PRODUCTS_DIR=".build/$(uname -m)-apple-macosx/release"
SPARKLE_FRAMEWORK="$BUILD_PRODUCTS_DIR/Sparkle.framework"
SPARKLE_BIN_DIR=".build/artifacts/sparkle/Sparkle/bin"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON_BASENAME="TrafficBarIcon-$VERSION"
ICONSET_DIR="$DIST_DIR/$ICON_BASENAME.iconset"
ICON_FILE="$DIST_DIR/$ICON_BASENAME.icns"
DMG_BACKGROUND="$DIST_DIR/TrafficBarInstallerBackground.png"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -n "$VERSION" ]] || die "VERSION is empty"

swift build -c release

mkdir -p Resources "$DIST_DIR"
swiftc scripts/make-icon.swift -o "$DIST_DIR/.make-icon"
"$DIST_DIR/.make-icon" Resources/TrafficBarIcon.png
swiftc scripts/make-dmg-background.swift -o "$DIST_DIR/.make-dmg-background"
"$DIST_DIR/.make-dmg-background" "$DMG_BACKGROUND"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 Resources/TrafficBarIcon.png --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp Resources/TrafficBarIcon.png "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
cp "$BUILD_PRODUCTS_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/$ICON_BASENAME.icns"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE.txt"
cp NOTICE.md "$APP_DIR/Contents/Resources/NOTICE.txt"
cp THIRD-PARTY-NOTICES/README.md "$APP_DIR/Contents/Resources/THIRD-PARTY-NOTICES.txt"
cp THIRD-PARTY-NOTICES/Sparkle-LICENSE.txt "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"

FEED_URL=""
if [[ -n "$REPOSITORY" ]]; then
    FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>流量管家</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>$ICON_BASENAME.icns</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>流量管家</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>SUEnableAutomaticChecks</key><true/>
PLIST

if [[ -n "$FEED_URL" && -n "$PUBLIC_KEY" ]]; then
    cat >> "$APP_DIR/Contents/Info.plist" <<PLIST
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
PLIST
fi

cat >> "$APP_DIR/Contents/Info.plist" <<PLIST
</dict>
</plist>
PLIST

install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null

ARCH="$(uname -m)"
DMG="$DIST_DIR/${APP_NAME}-macos-${ARCH}.dmg"
ARCHIVE="$DIST_DIR/${APP_NAME}-macos-${ARCH}.tar.gz"
APPCAST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trafficbar-appcast.XXXXXX")"
trap 'rm -rf "$APPCAST_DIR" "$DIST_DIR/.make-icon" "$DIST_DIR/.make-dmg-background" "$DMG_BACKGROUND" "$ICONSET_DIR"' EXIT
bash scripts/create-dmg.sh "$APP_DIR" "$DMG" "$DMG_BACKGROUND"
tar -czf "$ARCHIVE" -C "$DIST_DIR" "$APP_NAME.app"
shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
shasum -a 256 "$ARCHIVE" | awk '{print $1}' > "$ARCHIVE.sha256"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" && -n "$REPOSITORY" ]]; then
    [[ -x "$SPARKLE_BIN_DIR/generate_appcast" ]] || die "Sparkle generate_appcast not found"
    rm -f "$DIST_DIR/appcast.xml"
    cp "$DMG" "$APPCAST_DIR/"
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN_DIR/generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "https://github.com/$REPOSITORY/releases/download/v$VERSION/" \
        --embed-release-notes \
        -o "$DIST_DIR/appcast.xml" \
        "$APPCAST_DIR"
fi

printf 'Built %s\n' "$APP_DIR"
printf 'DMG: %s\n' "$DMG"
