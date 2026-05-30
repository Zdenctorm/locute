#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${APP_PATH:-${DIST_DIR}/Locute.app}"
DMG_PATH="${DMG_PATH:-${DIST_DIR}/Locute.dmg}"
STAGING_DIR="${ROOT_DIR}/build/dmg-staging"
BACKGROUND_SOURCE="${ROOT_DIR}/Design/dmg-background.png"
BACKGROUND_DIR="${STAGING_DIR}/.background"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle: ${APP_PATH}" >&2
  echo "Run scripts/build_release.sh first." >&2
  exit 1
fi

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}" "${BACKGROUND_DIR}"

ditto "${APP_PATH}" "${STAGING_DIR}/Locute.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if [[ -f "${BACKGROUND_SOURCE}" ]]; then
  ditto "${BACKGROUND_SOURCE}" "${BACKGROUND_DIR}/background.png"
fi

cat > "${STAGING_DIR}/README.txt" <<'EOF'
Locute

1. Pretahnete Locute do Applications.
2. Spustte aplikaci.
3. Povolte mikrofon a Zpristupneni.
4. Kliknete do textoveho pole, podrzte pravy Option, mluvte cesky a pustte.

Audio i text zustavaji na tomto Macu.
EOF

hdiutil create \
  -volname "Locute" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
