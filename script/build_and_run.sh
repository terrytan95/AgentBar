#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AgentBar"
BUNDLE_ID="com.terrytan.AgentBar"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="2.5.8"
APP_BUILD="246"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RUN_DIST_DIR="${AGENTBAR_RUN_DIST_DIR:-${TMPDIR:-/tmp}/AgentBar}"
BUILD_SCRATCH_DIR="${AGENTBAR_BUILD_DIR:-${TMPDIR:-/tmp}/AgentBar-build}"
CODESIGN_IDENTITY="${AGENTBAR_CODESIGN_IDENTITY:-}"

if [ -z "$CODESIGN_IDENTITY" ] && command -v security >/dev/null 2>&1; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' \
    | sed -n '1p')"
fi
if [ -z "$CODESIGN_IDENTITY" ] && command -v security >/dev/null 2>&1; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/.*"(AgentBar Local Code Signing)".*/\1/p' \
    | sed -n '1p')"
fi
if [ -z "$CODESIGN_IDENTITY" ] \
  && [ "$MODE" != "--package" ] \
  && [ "$MODE" != "package" ] \
  && command -v security >/dev/null 2>&1; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "([^"]+)".*/\1/p' \
    | sed -n '1p')"
fi
if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY="-"
fi

if { [ "$MODE" = "--package" ] || [ "$MODE" = "package" ]; } \
  && [ "$CODESIGN_IDENTITY" = "-" ] \
  && [ "${AGENTBAR_ALLOW_ADHOC_PACKAGE:-0}" != "1" ]; then
  echo "error: packaging requires a stable code-signing identity so macOS can preserve Accessibility permission across updates." >&2
  echo "Install a Developer ID or AgentBar local signing certificate, or set AGENTBAR_CODESIGN_IDENTITY. Use AGENTBAR_ALLOW_ADHOC_PACKAGE=1 only for throwaway local builds." >&2
  exit 1
fi

if [ "$MODE" = "--package" ] || [ "$MODE" = "package" ]; then
  APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
else
  APP_BUNDLE="$RUN_DIST_DIR/$APP_NAME.app"
fi
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

SWIFT_BUILD_ARGS=(
  --scratch-path "$BUILD_SCRATCH_DIR"
  -c "$BUILD_CONFIGURATION"
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT_DIR=."
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=."
)
if [ -n "${AGENTBAR_SWIFT_BUILD_EXTRA_ARGS:-}" ]; then
  IFS=' ' read -r -a EXTRA_SWIFT_BUILD_ARGS <<< "$AGENTBAR_SWIFT_BUILD_EXTRA_ARGS"
  SWIFT_BUILD_ARGS+=("${EXTRA_SWIFT_BUILD_ARGS[@]}")
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_BIN_PATH="$(swift build \
  --scratch-path "$BUILD_SCRATCH_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --show-bin-path
)"
BUILD_BINARY="$BUILD_BIN_PATH/$APP_NAME"

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
  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "warning: ad-hoc signing changes app identity on every build; Accessibility permission will not survive replacement." >&2
    codesign --force --deep --sign - "$APP_BUNDLE"
  elif [[ "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
  else
    codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
  fi
fi

open_app() {
  (cd / && /usr/bin/open -n "$APP_BUNDLE")
}

assert_no_embedded_build_paths() {
  local offender
  if offender="$(strings "$APP_BINARY" | grep -F -m1 -e "$ROOT_DIR" -e "$BUILD_SCRATCH_DIR")"; then
    echo "error: $APP_BINARY embeds local build/source path: $offender" >&2
    exit 1
  fi
}

case "$MODE" in
  --verify|verify|--package|package)
    assert_no_embedded_build_paths
    ;;
esac

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
