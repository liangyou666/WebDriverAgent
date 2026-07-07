#!/bin/bash
#
# Build an UNSIGNED WebDriverAgent for real iOS devices
# Designed for GitHub Actions macOS runner — no Apple ID needed at build time.
# Signing is done separately on Windows via zsign + free Apple ID cert/profile.
#

set -ex

SCHEME="${SCHEME:-WebDriverAgentRunner}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$(pwd)/wda-derived-data}"
WD="${WD:-$(pwd)/wda-build-output}"
ZIP_PKG_NAME="WebDriverAgent-Runner.zip"

mkdir -p "$WD"
rm -rf "$DERIVED_DATA_PATH" "$WD"/*

echo "=== Xcode version ==="
xcodebuild -version

echo "=== Build WebDriverAgentRunner for real iOS device (arm64, unsigned) ==="
# Use the same approach as WDA's own CI — CODE_SIGNING_ALLOWED=NO
xcodebuild clean build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  | tee "$WD/xcodebuild.log"

# ── Locate the built .app ──────────────────────────────────────
BUNDLE_PATH=$(find "$DERIVED_DATA_PATH" -name "${SCHEME}-Runner.app" -type d | head -1)
if [ -z "$BUNDLE_PATH" ]; then
  echo "ERROR: Could not find ${SCHEME}-Runner.app in derived data"
  find "$DERIVED_DATA_PATH" -name "*.app" -type d
  exit 1
fi

echo "=== Found app bundle: $BUNDLE_PATH ==="

# ── Package as zip (strip unnecessary frameworks for real device) ──
pushd "$(dirname "$BUNDLE_PATH")"
zip -qr "$WD/$ZIP_PKG_NAME" "$(basename "$BUNDLE_PATH")" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/XC*.framework*" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/Testing.framework*" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/libXCTestSwiftSupport.dylib"
popd

echo "=== Build artifacts ==="
echo "  App bundle: $BUNDLE_PATH"
echo "  Zip:        $WD/$ZIP_PKG_NAME"
echo ""
echo "=== Next step: sign this .app on Windows with zsign + free Apple ID ==="
