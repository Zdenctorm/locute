#!/usr/bin/env bash
# Build Dictator from this repo and install a single canonical copy (default: /Applications).
# Use this instead of running ad-hoc builds from Xcode DerivedData or multiple DMG installs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="${ROOT_DIR}/dist/Dictator.app"
INSTALL_PATH="${DICTATOR_INSTALL_PATH:-/Applications/Dictator.app}"
PULL=false
OPEN=true
SKIP_BUILD=false
LIST_ONLY=false

usage() {
  cat <<'EOF'
Usage: scripts/install_latest.sh [options]

Builds Release from the current checkout and replaces the canonical Dictator.app.

Options:
  --pull        git pull --ff-only origin main before building
  --skip-build  install existing dist/Dictator.app (must exist)
  --no-open     do not launch Dictator after install
  --list        print other Dictator.app copies on disk and exit
  -h, --help    show this help

Environment:
  DICTATOR_INSTALL_PATH   install target (default: /Applications/Dictator.app)

After install, grant Accessibility to THIS copy (see path in Nastavení → Oprávnění).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) PULL=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --no-open) OPEN=false; shift ;;
    --list) LIST_ONLY=true; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dictator can only be built and installed on macOS." >&2
  exit 1
fi

find_other_copies() {
  local canonical="${1:-}"
  local path

  if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      [[ -n "${canonical}" && "${path}" == "${canonical}" ]] && continue
      printf '%s\n' "${path}"
    done < <(mdfind "kMDItemCFBundleIdentifier == 'com.example.dictator'" 2>/dev/null || true)
  fi

  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    [[ -n "${canonical}" && "${path}" == "${canonical}" ]] && continue
    printf '%s\n' "${path}"
  done < <(
    find /Applications "${HOME}/Applications" \
      "${ROOT_DIR}/dist" "${ROOT_DIR}/build" \
      "${HOME}/Library/Developer/Xcode/DerivedData" \
      -name 'Dictator.app' -type d 2>/dev/null || true
  )
}

if [[ "${LIST_ONLY}" == true ]]; then
  echo "Kanonická kopie (cíl instalace): ${INSTALL_PATH}"
  echo ""
  echo "Ostatní kopie Dictator.app:"
  mapfile -t OTHERS < <(find_other_copies "${INSTALL_PATH}" | sort -u)
  if [[ ${#OTHERS[@]} -eq 0 ]]; then
    echo "  (žádné další nalezené)"
  else
    printf '  - %s\n' "${OTHERS[@]}"
  fi
  exit 0
fi

if [[ "${PULL}" == true ]]; then
  git -C "${ROOT_DIR}" pull --ff-only origin main
fi

if [[ "${SKIP_BUILD}" != true ]]; then
  "${ROOT_DIR}/scripts/build_release.sh"
fi

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "Missing build output: ${BUILT_APP}" >&2
  echo "Run without --skip-build, or build first: ./scripts/build_release.sh" >&2
  exit 1
fi

if pgrep -x Dictator >/dev/null 2>&1; then
  osascript -e 'tell application "Dictator" to quit' 2>/dev/null || true
  for _ in {1..40}; do
    pgrep -x Dictator >/dev/null || break
    sleep 0.25
  done
  if pgrep -x Dictator >/dev/null 2>&1; then
    pkill -x Dictator 2>/dev/null || true
    sleep 0.5
  fi
fi

mkdir -p "$(dirname "${INSTALL_PATH}")"
rm -rf "${INSTALL_PATH}"
ditto "${BUILT_APP}" "${INSTALL_PATH}"

VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${INSTALL_PATH}/Contents/Info.plist" 2>/dev/null || echo "?"
)"
BUILD="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "${INSTALL_PATH}/Contents/Info.plist" 2>/dev/null || echo "?"
)"

echo "Installed Dictator ${VERSION} (build ${BUILD})"
echo "  → ${INSTALL_PATH}"

mapfile -t OTHERS < <(find_other_copies "${INSTALL_PATH}" | sort -u)
if [[ ${#OTHERS[@]} -gt 0 ]]; then
  echo ""
  echo "Další kopie na disku (nepoužívej je — smaž nebo ignoruj):"
  printf '  - %s\n' "${OTHERS[@]}"
  echo ""
  echo "V Nastavení → Soukromí → Zpřístupnění nech jen tuto kopii."
fi

if [[ "${OPEN}" == true ]]; then
  open "${INSTALL_PATH}"
fi
