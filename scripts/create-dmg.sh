#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || {
    printf 'usage: %s APP_PATH OUTPUT_DMG BACKGROUND_PNG\n' "$0" >&2
    exit 1
}

APP_PATH="$1"
OUTPUT_DMG="$2"
BACKGROUND_PNG="$3"
VOLUME_NAME="流量管家"
APP_DISPLAY_NAME="流量管家.app"
APPLICATIONS_NAME="应用程序"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trafficbar-dmg-layout.XXXXXX")"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
RW_DMG="$WORK_DIR/TrafficBar-rw.dmg"
ATTACHED=0

detach_volume() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
            ATTACHED=0
            return 0
        fi
        sleep 1
    done

    hdiutil detach "$MOUNT_DIR" -force >/dev/null
    ATTACHED=0
}

cleanup() {
    if [[ "$ATTACHED" -eq 1 ]]; then
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

[[ -d "$APP_PATH" ]] || {
    printf 'error: app not found: %s\n' "$APP_PATH" >&2
    exit 1
}
[[ -f "$BACKGROUND_PNG" ]] || {
    printf 'error: background not found: %s\n' "$BACKGROUND_PNG" >&2
    exit 1
}

[[ ! -e "$MOUNT_DIR" ]] || {
    printf 'error: volume already mounted: %s\n' "$MOUNT_DIR" >&2
    exit 1
}
hdiutil create \
    -size 64m \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    "$RW_DMG" >/dev/null
hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$RW_DMG" >/dev/null
ATTACHED=1

ditto "$APP_PATH" "$MOUNT_DIR/$APP_DISPLAY_NAME"
ln -s /Applications "$MOUNT_DIR/$APPLICATIONS_NAME"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_PNG" "$MOUNT_DIR/.background/installer-background.png"
chflags hidden "$MOUNT_DIR/.background"
touch "$MOUNT_DIR/.metadata_never_index"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {120, 120, 780, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:installer-background.png"
        set position of item "$APP_DISPLAY_NAME" to {160, 235}
        set position of item "$APPLICATIONS_NAME" to {500, 235}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Spotlight-V100" "$MOUNT_DIR/.Trashes"
sync
detach_volume

rm -f "$OUTPUT_DMG"
hdiutil convert \
    "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG" >/dev/null
