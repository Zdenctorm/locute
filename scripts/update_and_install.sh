#!/usr/bin/env bash
# Pull current branch, then run install_latest.sh (same flags).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
branch="$(git -C "${ROOT_DIR}" symbolic-ref -q --short HEAD 2>/dev/null || true)"
if [[ -z "${branch}" ]]; then
  echo "Checkout a branch first (not detached HEAD)." >&2
  exit 1
fi
git -C "${ROOT_DIR}" fetch origin "${branch}"
git -C "${ROOT_DIR}" pull --ff-only origin "${branch}"
exec "${ROOT_DIR}/scripts/install_latest.sh" "$@"
