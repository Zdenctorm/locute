#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/build/DerivedData"
SOURCE_PACKAGES_PATH="${ROOT_DIR}/build/SourcePackages"
DIST_DIR="${ROOT_DIR}/dist"
APP_SOURCE="${DERIVED_DATA_PATH}/Build/Products/Release/Dictator.app"
APP_DIST="${DIST_DIR}/Dictator.app"

mkdir -p "${DIST_DIR}" "${SOURCE_PACKAGES_PATH}"
rm -rf "${APP_DIST}"

if ! xcrun --find metal >/dev/null 2>&1; then
  echo "Chybí Metal Toolchain (potřebný pro MLX / lokální post-processing)." >&2
  echo "Stáhni ho v Xcode nebo spusť:" >&2
  echo "  xcodebuild -downloadComponent MetalToolchain" >&2
  echo "Pak znovu: ./scripts/build_release.sh" >&2
  exit 1
fi

xcodebuild \
  -project "${ROOT_DIR}/Dictator.xcodeproj" \
  -scheme "Dictator" \
  -configuration "Release" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

ditto "${APP_SOURCE}" "${APP_DIST}"

# xcodebuild with CODE_SIGNING_ALLOWED=NO leaves the main binary linker-signed while
# embedded Sparkle helpers are adhoc/runtime — dyld then aborts with mismatched Team IDs.
# Re-sign inside-out so every Mach-O shares one identity (adhoc "-" for local dist).
ENTITLEMENTS="${ROOT_DIR}/Dictator/Resources/Dictator.entitlements" \
  "${ROOT_DIR}/scripts/codesign_app_bundle.sh" "${APP_DIST}" "-"

"${ROOT_DIR}/scripts/create_dmg.sh"

echo "Release app: ${APP_DIST}"
echo "DMG: ${DIST_DIR}/Dictator.dmg"
