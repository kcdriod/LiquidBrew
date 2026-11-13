#!/usr/bin/env zsh
set -euo pipefail
cd "${0:A:h:h}"

VERSION="${1:-1.0.0}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ]]; then
  print -u2 "Usage: ./scripts/build_dmg.sh 1.0.0[-prerelease]"
  exit 1
fi
APP_PATH="$PWD/LiquidBrew.app"
if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Build LiquidBrew.app with ./build_app.sh first."
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/LiquidBrew" -verify_arch arm64
lipo "$APP_PATH/Contents/MacOS/LiquidBrew" -verify_arch x86_64

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liquidbrew-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_PATH" "$STAGING_DIR/LiquidBrew.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/Install.txt" <<'EOF'
LiquidBrew — a native Homebrew manager for macOS 26 or newer.

Drag LiquidBrew.app onto the Applications shortcut, then open it from Applications.
Homebrew must already be installed: https://brew.sh

Community builds are ad-hoc signed, not Apple-notarized. macOS may show a
Gatekeeper warning. Only install a build whose source and origin you trust.

Source, documentation and contributions: https://github.com/kcdriod/LiquidBrew
EOF
mkdir -p dist
DMG_NAME="LiquidBrew-${VERSION}-universal.dmg"
hdiutil create -volname "LiquidBrew" -srcfolder "$STAGING_DIR" -ov -format UDZO "$PWD/dist/$DMG_NAME"
hdiutil verify "$PWD/dist/$DMG_NAME"
(
  cd dist
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
print "Created dist/$DMG_NAME and its SHA-256 checksum."
