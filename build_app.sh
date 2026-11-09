#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="LiquidBrew"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --show-sdk-path)"
fi

echo "==> Building ${APP_NAME} with SDK ${SDK_PATH}..."
swift build --sdk "$SDK_PATH"

BIN_PATH="$(find .build -name "${APP_NAME}" -type f -perm +111 | head -n 1)"
if [[ -z "$BIN_PATH" ]]; then
  echo "Error: Could not locate compiled binary for ${APP_NAME}"
  exit 1
fi

echo "==> Packaging ${BUNDLE_DIR} from ${BIN_PATH}..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"

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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null 2>&1 || true
echo "==> Successfully created ${BUNDLE_DIR}!"
