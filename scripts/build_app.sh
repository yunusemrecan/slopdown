#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build Slopdown.app (macOS).
#
#   scripts/build_app.sh [--arch arm64|x86_64] [--debug]
#
# Output: dist/Slopdown.app and dist/Slopdown-macos-<arch>.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="arm64"
CONFIG="release"
VERSION="${SLOPDOWN_VERSION:-0.1.0}"
AUTOTEST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --debug) CONFIG="debug"; shift ;;
        --autotest) AUTOTEST=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

DIST="$ROOT/dist"
APP="$DIST/Slopdown.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Building ($CONFIG, $ARCH)"
# The visual self-test (SLOPDOWN_AUTOTEST) is compiled in only for CI test builds.
FLAGS=()
if [[ "$AUTOTEST" == 1 ]]; then FLAGS=(-Xswiftc -DSLOPDOWN_AUTOTEST); fi
swift build --package-path "$ROOT" -c "$CONFIG" --arch "$ARCH" --product Slopdown ${FLAGS[@]+"${FLAGS[@]}"}
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --arch "$ARCH" --show-bin-path ${FLAGS[@]+"${FLAGS[@]}"})"
cp "$BIN_DIR/Slopdown" "$APP/Contents/MacOS/Slopdown"

echo "==> Info.plist"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD_NUMBER/" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
for lproj in "$ROOT"/Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
# Hardened runtime: no injected libraries, no DYLD_* tricks.
codesign --force --sign - --timestamp=none --options runtime "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> Zipping"
rm -f "$DIST/Slopdown-macos-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Slopdown-macos-$ARCH.zip"

echo "Done: $APP"
