#!/usr/bin/env zsh
set -euo pipefail

cd "${0:A:h:h}"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

BUILD_FLAGS=(--disable-sandbox --configuration release --product LiquidBrewCLI)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build --disable-sandbox --configuration release --show-bin-path)"
INSTALL_DIR="${LIQUIDBREW_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.liquidbrew-install.XXXXXX")"
install -m 755 "$BIN_DIR/LiquidBrewCLI" "$STAGING_DIR/liquidbrew"
codesign --force --sign - "$STAGING_DIR/liquidbrew"
codesign --verify --strict "$STAGING_DIR/liquidbrew"
mv -f "$STAGING_DIR/liquidbrew" "$INSTALL_DIR/liquidbrew"
rmdir "$STAGING_DIR"
print "Installed $INSTALL_DIR/liquidbrew"
print "Run liquidbrew to open the terminal workspace, or liquidbrew --demo to preview it."
