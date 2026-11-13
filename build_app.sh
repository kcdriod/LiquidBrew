#!/usr/bin/env zsh
set -euo pipefail

cd "${0:A:h}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
if [[ "$BUILD_CONFIGURATION" != debug && "$BUILD_CONFIGURATION" != release ]]; then
  print -u2 "BUILD_CONFIGURATION must be debug or release."
  exit 1
fi
if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$APP_BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  print -u2 "Use a numeric major.minor.patch APP_VERSION and integer APP_BUILD_NUMBER."
  exit 1
fi

APP_NAME="LiquidBrew"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Use full Xcode so SwiftUI compiler plugins match the selected SDK.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"

BUILD_FLAGS=(--disable-sandbox --configuration "$BUILD_CONFIGURATION" --scratch-path "${SWIFT_BUILD_PATH:-.build}" --sdk "$SDK_PATH")
for architecture in ${=BUILD_ARCHS:-}; do
  if [[ "$architecture" != arm64 && "$architecture" != x86_64 ]]; then
    print -u2 "BUILD_ARCHS supports arm64 and x86_64."
    exit 1
  fi
  BUILD_FLAGS+=(--arch "$architecture")
done
swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/${APP_NAME}"

echo "==> Packaging ${BUNDLE_DIR} from ${BIN_PATH}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"

# Render the full macOS icon family from the generated source artwork.
ICON_SOURCE="$PWD/Assets/AppIcon.png"
ICON_SET="${SWIFT_BUILD_PATH:-.build}/AppIcon.iconset"
mkdir -p "$ICON_SET"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$ICON_SOURCE" --out "$ICON_SET/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" "$ICON_SOURCE" --out "$ICON_SET/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.liquidbrew.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>LiquidBrew</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$BUNDLE_DIR"
codesign --verify --deep --strict "$BUNDLE_DIR"
echo "==> Successfully created ${BUNDLE_DIR}!"
