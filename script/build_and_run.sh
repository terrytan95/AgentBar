#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AgentBar"
BUNDLE_ID="com.terrytan.AgentBar"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="1.3.10"
APP_BUILD="152"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

BUILD_CONFIGURATION="debug"
if [ "$MODE" = "--package" ] || [ "$MODE" = "package" ]; then
  BUILD_CONFIGURATION="release"
fi

SWIFT_BUILD_ARGS=(-c "$BUILD_CONFIGURATION")
if [ -n "${AGENTBAR_SWIFT_BUILD_EXTRA_ARGS:-}" ]; then
  IFS=' ' read -r -a EXTRA_SWIFT_BUILD_ARGS <<< "$AGENTBAR_SWIFT_BUILD_EXTRA_ARGS"
  SWIFT_BUILD_ARGS+=("${EXTRA_SWIFT_BUILD_ARGS[@]}")
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_BINARY="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ "$BUILD_CONFIGURATION" = "release" ] && command -v strip >/dev/null 2>&1; then
  strip -S -x "$APP_BINARY" >/dev/null 2>&1 || true
fi
if [ -d "$ROOT_DIR/Sources/AgentBar/Resources" ]; then
  cp -R "$ROOT_DIR/Sources/AgentBar/Resources/." "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AgentBarIcon</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_BUNDLE"
    ;;
  --smoke-report|smoke-report)
    REPORT_PATH="${2:-$ROOT_DIR/verification/agentbar-smoke-report.txt}"
    "$APP_BINARY" --smoke-report "$REPORT_PATH" >/dev/null 2>&1 || true
    echo "$REPORT_PATH"
    ;;
  --package|package)
    echo "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
