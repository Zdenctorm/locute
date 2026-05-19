#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/build/DerivedData"
SOURCE_PACKAGES_PATH="${ROOT_DIR}/build/SourcePackages"
DIST_DIR="${ROOT_DIR}/dist"
APP_SOURCE="${DERIVED_DATA_PATH}/Build/Products/Release/Dictator.app"
APP_DIST="${DIST_DIR}/Dictator.app"
ENTITLEMENTS="${ROOT_DIR}/Dictator/Resources/Dictator.entitlements"

mkdir -p "${DIST_DIR}" "${SOURCE_PACKAGES_PATH}"
rm -rf "${APP_DIST}"

xcodebuild \
  -project "${ROOT_DIR}/Dictator.xcodeproj" \
  -scheme "Dictator" \
  -configuration "Release" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

ditto "${APP_SOURCE}" "${APP_DIST}"

# Xcode can leave an unsigned local build with a partial Mach-O signature.
# Ad-hoc signing makes the copied app bundle internally consistent for local testing.
codesign \
  --force \
  --deep \
  --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign - \
  "${APP_DIST}"

codesign --verify --deep --strict --verbose=2 "${APP_DIST}"

"${ROOT_DIR}/scripts/create_dmg.sh"

echo "Release app: ${APP_DIST}"
echo "DMG: ${DIST_DIR}/Dictator.dmg"
