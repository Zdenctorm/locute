#!/usr/bin/env bash
# Bootstrap .impeccable/ pro Locute (critique dir, ignore template).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMPECCABLE_DIR="${ROOT_DIR}/.impeccable"
CRITIQUE_DIR="${IMPECCABLE_DIR}/critique"
IGNORE_FILE="${CRITIQUE_DIR}/ignore.md"
TEMPLATE="${ROOT_DIR}/impeccable/templates/critique-ignore.md"

mkdir -p "${CRITIQUE_DIR}"

if [[ ! -f "${IGNORE_FILE}" ]]; then
  if [[ -f "${ROOT_DIR}/.impeccable/critique/ignore.md" ]] && [[ "${IGNORE_FILE}" != "${TEMPLATE}" ]]; then
    : # committed ignore already in place
  elif [[ -f "${TEMPLATE}" ]]; then
    cp "${TEMPLATE}" "${IGNORE_FILE}"
  else
    echo "# Critique ignore — Locute" > "${IGNORE_FILE}"
    echo "" >> "${IGNORE_FILE}"
    echo "Přidávej substringy nálezů, které mají critique přeskočit." >> "${IGNORE_FILE}"
  fi
  echo "Created ${IGNORE_FILE}"
else
  echo "Already exists: ${IGNORE_FILE}"
fi

if [[ -f "${ROOT_DIR}/DESIGN.json" ]] && [[ ! -f "${IMPECCABLE_DIR}/design.json" ]]; then
  cp "${ROOT_DIR}/DESIGN.json" "${IMPECCABLE_DIR}/design.json"
  echo "Copied DESIGN.json → .impeccable/design.json"
fi

echo "Impeccable bootstrap done. See IMPECCABLE.md"
