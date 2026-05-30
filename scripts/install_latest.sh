#!/usr/bin/env bash
# Build Dictator from this repo and install a single canonical copy (default: /Applications).
# Use this instead of running ad-hoc builds from Xcode DerivedData or multiple DMG installs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]}"

# When the checkout is behind origin, pull and re-exec so new script flags (e.g. --clean) work.
maybe_reexec_if_behind_origin() {
  [[ "${DICTATOR_INSTALL_REEXEC:-0}" == "1" ]] && return 0
  git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local branch
  branch="$(git -C "${ROOT_DIR}" symbolic-ref -q --short HEAD 2>/dev/null || true)"
  [[ -n "${branch}" ]] || return 0

  git -C "${ROOT_DIR}" fetch origin "${branch}" 2>/dev/null || return 0

  local upstream="origin/${branch}"
  git -C "${ROOT_DIR}" rev-parse --verify "${upstream}" >/dev/null 2>&1 || return 0

  local behind
  behind="$(git -C "${ROOT_DIR}" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
  [[ "${behind}" -gt 0 ]] || return 0

  echo "Repo je ${behind} commit(y) za ${upstream}; stahuji a spouštím instalaci znovu…"
  git -C "${ROOT_DIR}" pull --ff-only origin "${branch}"
  export DICTATOR_INSTALL_REEXEC=1
  exec "${ROOT_DIR}/scripts/$(basename "${SCRIPT_PATH}")" "$@"
}
maybe_reexec_if_behind_origin "$@"

BUILT_APP="${ROOT_DIR}/dist/Dictator.app"
INSTALL_PATH="${DICTATOR_INSTALL_PATH:-/Applications/Dictator.app}"
PULL=false
OPEN=true
SKIP_BUILD=false
LIST_ONLY=false
CLEAN=false

usage() {
  cat <<'EOF'
Usage: scripts/install_latest.sh [options]

Builds Release from the current checkout and replaces the canonical Dictator.app.

Options:
  --pull        git fetch + pull --ff-only for the current branch before building
  --clean       remove build/DerivedData before building (full recompile)
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
    --clean) CLEAN=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --no-open) OPEN=false; shift ;;
    --list) LIST_ONLY=true; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      if [[ "$1" == "--clean" ]]; then
        echo "Tip: nejdřív aktualizuj repo (skript je starší než origin):" >&2
        echo "  git pull --ff-only origin $(git -C "${ROOT_DIR}" symbolic-ref -q --short HEAD 2>/dev/null || echo '<větev>')" >&2
      fi
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Dictator can only be built and installed on macOS." >&2
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/Dictator.xcodeproj/project.pbxproj" ]]; then
  echo "Tady není Dictator repo: ${ROOT_DIR}" >&2
  echo "Použij např.: cd ~/dictator && ./scripts/install_latest.sh" >&2
  echo "(NE cd ~/anycoin/dictator — to zdvojí jméno složky uživatele.)" >&2
  exit 1
fi

print_git_head() {
  if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git: $(git -C "${ROOT_DIR}" rev-parse --short HEAD) ($(git -C "${ROOT_DIR}" log -1 --format='%s'))"
  else
    echo "Git: (není git repo — clone z github.com/Zdenctorm/dictator)" >&2
    exit 1
  fi
}

current_git_branch() {
  git -C "${ROOT_DIR}" symbolic-ref -q --short HEAD 2>/dev/null || true
}

# Bash 3.2 (macOS default) has no mapfile — print paths one per line.
print_other_copies() {
  local canonical="${1:-}"
  local path
  local found=false

  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    if [[ "${found}" == false ]]; then
      found=true
    fi
    printf '  - %s\n' "${path}"
  done < <(find_other_copies "${canonical}" | sort -u)

  if [[ "${found}" == false ]]; then
    echo "  (žádné další nalezené)"
  fi
}

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

ensure_branch_not_behind_origin() {
  local branch="$1"
  local upstream="origin/${branch}"
  local behind

  if ! git -C "${ROOT_DIR}" rev-parse --verify "${upstream}" >/dev/null 2>&1; then
    return 0
  fi

  behind="$(git -C "${ROOT_DIR}" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"
  if [[ "${behind}" -eq 0 ]]; then
    return 0
  fi

  echo "" >&2
  echo "Chyba: větev '${branch}' je ${behind} commit(y) za ${upstream}." >&2
  echo "  git pull --ff-only origin ${branch}" >&2
  echo "nebo spusť znovu s: ./scripts/install_latest.sh --pull" >&2
  echo "" >&2
  exit 1
}

sync_git_if_requested() {
  local branch
  branch="$(current_git_branch)"
  if [[ -z "${branch}" ]]; then
    if [[ "${PULL}" == true ]]; then
      echo "Nelze použít --pull v detached HEAD — checkout větev nejdřív." >&2
      exit 1
    fi
    return 0
  fi

  git -C "${ROOT_DIR}" fetch origin "${branch}" 2>/dev/null || {
    echo "Varování: git fetch origin ${branch} selhalo (offline?)." >&2
    return 0
  }

  if [[ "${PULL}" == true ]]; then
    git -C "${ROOT_DIR}" pull --ff-only origin "${branch}"
    echo "Po pull:"
    print_git_head
    return 0
  fi

  ensure_branch_not_behind_origin "${branch}"
}

if [[ "${LIST_ONLY}" == true ]]; then
  echo "Kanonická kopie (cíl instalace): ${INSTALL_PATH}"
  echo ""
  echo "Ostatní kopie Dictator.app:"
  print_other_copies "${INSTALL_PATH}"
  exit 0
fi

echo "Repo: ${ROOT_DIR}"
print_git_head

sync_git_if_requested

if [[ "${SKIP_BUILD}" != true ]]; then
  if [[ "${CLEAN}" == true ]]; then
    echo "Čistý build: mažu ${ROOT_DIR}/build/DerivedData …"
    rm -rf "${ROOT_DIR}/build/DerivedData"
  fi
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

OTHERS_COUNT=0
while IFS= read -r _; do
  OTHERS_COUNT=$((OTHERS_COUNT + 1))
done < <(find_other_copies "${INSTALL_PATH}" | sort -u)

if [[ "${OTHERS_COUNT}" -gt 0 ]]; then
  echo ""
  echo "Další kopie na disku (nepoužívej je — smaž nebo ignoruj):"
  print_other_copies "${INSTALL_PATH}"
  echo ""
  echo "V Nastavení → Soukromí → Zpřístupnění nech jen tuto kopii."
fi

if [[ "${OPEN}" == true ]]; then
  open "${INSTALL_PATH}"
fi
