#!/bin/bash
#
# Build a SIGNED WebDriverAgent IPA for real iOS devices
# Designed for GitHub Actions macOS runner (or any Mac)
#
# Required environment variables:
#   APPLE_ID          - Your Apple ID email
#   APPLE_TEAM_ID     - Your Personal Team ID (find in Apple Developer or Xcode)
#   APPLE_APP_PASSWORD - App-specific password for your Apple ID
#   SCHEME            - Xcode scheme (default: WebDriverAgentRunner)
#   WD                - Working directory for build output (default: ./build)
#

set -ex

SCHEME="${SCHEME:-WebDriverAgentRunner}"
WD="${WD:-$(pwd)/wda-build-output}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$(pwd)/wda-derived-data}"
ZIP_PKG_NAME="WebDriverAgent-Runner.zip"
IPA_NAME="WebDriverAgent.ipa"

# ── Validate required env vars ──────────────────────────────────
for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var is not set. Add it as a GitHub Secret."
    exit 1
  fi
done

echo "=== Setup Keychain for signing ==="
KEYCHAIN_NAME="wda-build.keychain"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security default-keychain -s "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
# Extend unlock timeout to avoid CI timeout issues
security set-keychain-settings -t 3600 -l "$KEYCHAIN_NAME"

echo "=== Store Apple ID credentials in Keychain ==="
# Using the CI/CD pattern for Xcode automatic signing
security add-generic-password \
  -s "Xcode-Altool" \
  -a "$APPLE_ID" \
  -w "$APPLE_APP_PASSWORD" \
  -T /usr/bin/security \
  -T /usr/bin/codesign \
  -T /usr/bin/xcodebuild

mkdir -p "$WD"

echo "=== Clean any previous build artifacts ==="
rm -rf "$DERIVED_DATA_PATH" "$WD"/*

echo "=== Build WebDriverAgentRunner for real iOS device (arm64) ==="
xcodebuild clean build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyIssuerID "" \
  -authenticationKeyID "" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  | tee "$WD/xcodebuild.log"

# ── Locate the built .app ──────────────────────────────────────
BUNDLE_PATH=$(find "$DERIVED_DATA_PATH" -name "${SCHEME}-Runner.app" -type d | head -1)
if [ -z "$BUNDLE_PATH" ]; then
  echo "ERROR: Could not find ${SCHEME}-Runner.app in derived data"
  echo "Searching for any .app bundles..."
  find "$DERIVED_DATA_PATH" -name "*.app" -type d
  exit 1
fi

echo "=== Found app bundle: $BUNDLE_PATH ==="

# ── Verify signing ──────────────────────────────────────────────
echo "=== Verify code signature ==="
codesign -dv --verbose=4 "$BUNDLE_PATH" 2>&1 || true

# ── Create .ipa (Payload/ directory structure) ─────────────────
echo "=== Packaging as .ipa ==="
IPA_TEMP=$(mktemp -d)
mkdir -p "$IPA_TEMP/Payload"
cp -R "$BUNDLE_PATH" "$IPA_TEMP/Payload/"
pushd "$IPA_TEMP"
zip -qr "$WD/$IPA_NAME" Payload
popd
rm -rf "$IPA_TEMP"

echo "=== Clean build artifacts ==="
# Also create a zip of just the .app for go-ios installation
pushd "$(dirname "$BUNDLE_PATH")"
zip -qr "$WD/$ZIP_PKG_NAME" "$(basename "$BUNDLE_PATH")" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/XC*.framework*" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/Testing.framework*" \
  -x "$(basename "$BUNDLE_PATH")/Frameworks/libXCTestSwiftSupport.dylib"
popd

echo "=== Build artifacts ==="
echo "  IPA:  $WD/$IPA_NAME"
echo "  ZIP:  $WD/$ZIP_PKG_NAME"
echo ""
echo "=== IMPORTANT: Free Apple ID provisioning is valid for 7 days ==="
echo "=== Rebuild before it expires to keep WDA working ==="
