#!/usr/bin/env bash
# Re-sign a Locute.app bundle so every Mach-O shares the same Team ID.
# Required after Release builds with CODE_SIGNING_ALLOWED=NO (linker-signed main +
# adhoc Sparkle helpers otherwise crash dyld with "different Team IDs").
#
# Usage:
#   scripts/codesign_app_bundle.sh /path/to/Locute.app [signing_identity]
#
# signing_identity must be a Developer ID Application certificate (not "-").
set -euo pipefail

APP_PATH="${1:?Usage: $0 /path/to/Locute.app <signing_identity>}"
SIGN_ID="${2:?Signing identity required (Developer ID Application: …)}"

if [[ "${SIGN_ID}" == "-" ]]; then
  echo "Refusing ad-hoc identity: linker-signed Release builds must not be re-signed with '-'." >&2
  echo "Use the xcodebuild output from build_release.sh as-is, or pass a Developer ID cert." >&2
  exit 1
fi
ENTITLEMENTS="${ENTITLEMENTS:-}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Not a directory: ${APP_PATH}" >&2
  exit 1
fi

SPARKLE_FW="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_B="${SPARKLE_FW}/Versions/B"

if [[ ! -d "${SPARKLE_B}" ]]; then
  echo "Sparkle.framework missing under ${APP_PATH}" >&2
  exit 1
fi

TIMESTAMP_ARGS=(--timestamp)

sign_target() {
  local target="$1"
  if [[ -n "${ENTITLEMENTS}" && "${target}" == "${APP_PATH}" ]]; then
    codesign \
      --force \
      --options runtime \
      "${TIMESTAMP_ARGS[@]}" \
      --sign "${SIGN_ID}" \
      --entitlements "${ENTITLEMENTS}" \
      "${target}"
  else
    codesign \
      --force \
      --options runtime \
      "${TIMESTAMP_ARGS[@]}" \
      --sign "${SIGN_ID}" \
      "${target}"
  fi
}

# Strip stale signatures so every binary is signed with the same identity.
while IFS= read -r -d '' file; do
  if file "${file}" | grep -q 'Mach-O'; then
    codesign --remove-signature "${file}" 2>/dev/null || true
  fi
done < <(find "${APP_PATH}" -type f -print0)

# Deepest Sparkle helpers first, then the app bundle.
sign_target "${SPARKLE_B}/XPCServices/Downloader.xpc"
sign_target "${SPARKLE_B}/XPCServices/Installer.xpc"
sign_target "${SPARKLE_B}/Updater.app"
sign_target "${SPARKLE_B}/Autoupdate"
sign_target "${SPARKLE_FW}"
sign_target "${APP_PATH}/Contents/MacOS/Locute"
sign_target "${APP_PATH}"

codesign --verify --strict --verbose=2 "${APP_PATH}"
echo "Signed ${APP_PATH} with identity: ${SIGN_ID}"
