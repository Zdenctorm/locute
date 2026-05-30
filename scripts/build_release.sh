#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/build/DerivedData"
SOURCE_PACKAGES_PATH="${ROOT_DIR}/build/SourcePackages"
DIST_DIR="${ROOT_DIR}/dist"
APP_SOURCE="${DERIVED_DATA_PATH}/Build/Products/Release/Locute.app"
APP_DIST="${DIST_DIR}/Locute.app"

mkdir -p "${DIST_DIR}" "${SOURCE_PACKAGES_PATH}"
rm -rf "${APP_DIST}"

# SPM workspace-state.json stores absolute artifact paths; stale cache breaks builds after moving the repo.
WORKSPACE_STATE="${SOURCE_PACKAGES_PATH}/workspace-state.json"
if [[ -f "${WORKSPACE_STATE}" ]] && ! grep -q "\"${ROOT_DIR}/" "${WORKSPACE_STATE}"; then
  echo "Removing stale Swift package cache (project path changed)..." >&2
  rm -rf "${SOURCE_PACKAGES_PATH}"
  mkdir -p "${SOURCE_PACKAGES_PATH}"
fi

if ! xcrun --find metal >/dev/null 2>&1; then
  echo "Chybí Metal Toolchain (potřebný pro MLX / lokální post-processing)." >&2
  echo "Stáhni ho v Xcode nebo spusť:" >&2
  echo "  xcodebuild -downloadComponent MetalToolchain" >&2
  echo "Pak znovu: ./scripts/build_release.sh" >&2
  exit 1
fi

xcodebuild \
  -project "${ROOT_DIR}/Locute.xcodeproj" \
  -scheme "Locute" \
  -configuration "Release" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  build

ditto "${APP_SOURCE}" "${APP_DIST}"

# Do NOT ad-hoc re-sign here. xcodebuild leaves the main binary linker-signed and Sparkle
# helpers adhoc/runtime — that pair loads correctly. Re-signing the main executable with "-"
# breaks dyld ("different Team IDs"). For Developer ID distribution use sign_and_notarize.sh.

if ! codesign --verify --deep --strict --verbose=2 "${APP_DIST}"; then
  if [[ "${ALLOW_UNVERIFIED_LOCAL_BUILD:-0}" == "1" ]]; then
    echo "Warning: strict codesign verify failed, continuing because ALLOW_UNVERIFIED_LOCAL_BUILD=1." >&2
  else
    echo "Error: strict codesign verify failed for ${APP_DIST}." >&2
    echo "For distribution, run sign_and_notarize.sh with a Developer ID identity." >&2
    echo "For local-only testing, rerun with ALLOW_UNVERIFIED_LOCAL_BUILD=1." >&2
    exit 1
  fi
fi

"${ROOT_DIR}/scripts/create_dmg.sh"

echo "Release app: ${APP_DIST}"
echo "DMG: ${DIST_DIR}/Locute.dmg"
