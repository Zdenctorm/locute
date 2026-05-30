#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ok=0
warn=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo "OK   $1"
    ok=$((ok + 1))
  else
    echo "WARN $1"
    warn=$((warn + 1))
  fi
}

echo "Locute distribution environment check"
echo "---------------------------------------"

check "xcodebuild" "command -v xcodebuild"
check "codesign" "command -v codesign"
check "notarytool (xcrun)" "xcrun notarytool --version"
check "stapler (xcrun)" "xcrun stapler --version"
check "DEVELOPER_ID_APPLICATION set" "test -n \"\${DEVELOPER_ID_APPLICATION:-}\""
check "NOTARY_KEYCHAIN_PROFILE or Apple ID trio" \
  "test -n \"\${NOTARY_KEYCHAIN_PROFILE:-}\" || { test -n \"\${APPLE_ID:-}\" && test -n \"\${APPLE_TEAM_ID:-}\" && test -n \"\${APP_SPECIFIC_PASSWORD:-}\"; }"
check "Sparkle sign_update" "test -x \"${ROOT_DIR}/build/sparkle-tools/bin/sign_update\" || command -v sign_update"

echo "---------------------------------------"
echo "Ready checks: ${ok}, warnings: ${warn}"
if [[ "${warn}" -gt 0 ]]; then
  echo "Fix warnings before running ./scripts/sign_and_notarize.sh"
  exit 1
fi
echo "Environment looks ready for signed + notarized release."
