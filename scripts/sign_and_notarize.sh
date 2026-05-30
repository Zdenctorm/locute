#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${APP_PATH:-${DIST_DIR}/Locute.app}"
DMG_PATH="${DMG_PATH:-${DIST_DIR}/Locute.dmg}"
ENTITLEMENTS="${ROOT_DIR}/Locute/Resources/Locute.entitlements"

IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID_VALUE="${APPLE_ID:-}"
APPLE_TEAM_ID_VALUE="${APPLE_TEAM_ID:-}"
APP_PASSWORD_VALUE="${APP_SPECIFIC_PASSWORD:-}"

if [[ -z "${IDENTITY}" ]]; then
  echo "Missing DEVELOPER_ID_APPLICATION." >&2
  echo "Example: export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  "${ROOT_DIR}/scripts/build_release.sh"
fi

export ENTITLEMENTS
"${ROOT_DIR}/scripts/codesign_app_bundle.sh" "${APP_PATH}" "${IDENTITY}"
spctl --assess --type execute --verbose=2 "${APP_PATH}" || true

"${ROOT_DIR}/scripts/create_dmg.sh"

codesign \
  --force \
  --timestamp \
  --sign "${IDENTITY}" \
  "${DMG_PATH}"

if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
  xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait
else
  if [[ -z "${APPLE_ID_VALUE}" || -z "${APPLE_TEAM_ID_VALUE}" || -z "${APP_PASSWORD_VALUE}" ]]; then
    echo "Missing notarization credentials." >&2
    echo "Set NOTARY_KEYCHAIN_PROFILE, or set APPLE_ID, APPLE_TEAM_ID, and APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi

  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID_VALUE}" \
    --team-id "${APPLE_TEAM_ID_VALUE}" \
    --password "${APP_PASSWORD_VALUE}" \
    --wait
fi

xcrun stapler staple "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

echo "Signed and notarized DMG: ${DMG_PATH}"
