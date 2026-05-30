#!/usr/bin/env bash
set -euo pipefail

# Build + sign + publish a new Sparkle-update-capable release.
#
# Usage: scripts/release.sh <version> [release-notes-file]
#   version            e.g. 1.1.0 (sets CFBundleShortVersionString)
#   release-notes-file optional path to markdown notes; defaults to a stub
#
# Prereqs (one-time):
#   - scripts/build_release.sh works locally
#   - gh CLI authenticated (gh auth status)
#   - Sparkle tools downloaded: build/sparkle-tools/bin/{sign_update,generate_appcast}
#   - EdDSA keypair generated (generate_keys); private key lives in Keychain
#   - Info.plist already contains SUPublicEDKey + SUFeedURL

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

VERSION="${1:-}"
NOTES_FILE="${2:-}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version> [release-notes-file]" >&2
  exit 1
fi

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Version must look like 1.0 or 1.2.3 (got: ${VERSION})" >&2
  exit 1
fi

SPARKLE_BIN="${ROOT_DIR}/build/sparkle-tools/bin"
SIGN_UPDATE="${SPARKLE_BIN}/sign_update"
if [[ ! -x "${SIGN_UPDATE}" ]]; then
  echo "Missing Sparkle sign_update at ${SIGN_UPDATE}" >&2
  echo "Download Sparkle release tarball into build/sparkle-tools/ first." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required. brew install gh." >&2
  exit 1
fi

# Build number = epoch seconds. Monotonically increasing, easy to read.
BUILD_NUMBER="$(date +%s)"

PROJECT="${ROOT_DIR}/Locute.xcodeproj/project.pbxproj"

# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION across all configurations.
# pbxproj uses semicolon-terminated assignments; replace_all-style sed is safe here
# because both keys appear exactly twice (Debug + Release for Locute target, and
# twice more for the test target which we want to keep in lockstep).
/usr/bin/sed -i '' \
  -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${VERSION};/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" \
  "${PROJECT}"

echo "Bumped to version ${VERSION} (build ${BUILD_NUMBER})"

# Build + DMG via existing scripts.
"${ROOT_DIR}/scripts/build_release.sh"

DMG_PATH="${ROOT_DIR}/dist/Locute.dmg"
VERSIONED_DMG="${ROOT_DIR}/dist/Locute-${VERSION}.dmg"
cp "${DMG_PATH}" "${VERSIONED_DMG}"

# Sign DMG with Sparkle EdDSA key (private key is in Keychain).
echo "Signing DMG with Sparkle EdDSA key…"
SIGN_OUTPUT="$("${SIGN_UPDATE}" "${VERSIONED_DMG}")"
echo "  ${SIGN_OUTPUT}"

# sign_update prints: sparkle:edSignature="..." length="..."
EDSIGNATURE="$(echo "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "${SIGN_OUTPUT}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

if [[ -z "${EDSIGNATURE}" || -z "${LENGTH}" ]]; then
  echo "Failed to parse sign_update output" >&2
  exit 1
fi

# Release notes. Sparkle reads <description> as HTML; markdown stays readable as-is.
NOTES_TEXT=""
if [[ -n "${NOTES_FILE}" && -f "${NOTES_FILE}" ]]; then
  NOTES_TEXT="$(cat "${NOTES_FILE}")"
else
  NOTES_TEXT="Nová verze Locute."
fi

PUB_DATE="$(LC_ALL=C TZ=GMT date '+%a, %d %b %Y %H:%M:%S +0000')"
DOWNLOAD_URL="https://github.com/Zdenctorm/locute/releases/download/v${VERSION}/Locute-${VERSION}.dmg"

APPCAST="${ROOT_DIR}/appcast.xml"

# Read previous items (if any) to keep history. New item goes at the top.
PREVIOUS_ITEMS=""
if [[ -f "${APPCAST}" ]]; then
  PREVIOUS_ITEMS="$(/usr/bin/awk '
    /<item>/        { capture=1 }
    capture         { print }
    /<\/item>/      { capture=0; print "" }
  ' "${APPCAST}")"
fi

cat > "${APPCAST}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Locute</title>
        <link>https://github.com/Zdenctorm/locute</link>
        <description>Most recent updates to Locute</description>
        <language>cs</language>
        <item>
            <title>Verze ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
${NOTES_TEXT}
]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${EDSIGNATURE}" />
        </item>
${PREVIOUS_ITEMS}
    </channel>
</rss>
EOF

echo "appcast.xml updated"

# Commit version bump + appcast.
git add Locute.xcodeproj/project.pbxproj appcast.xml
git commit -m "Release v${VERSION}" || echo "(nothing to commit)"
git tag -f "v${VERSION}"
git push origin main
git push origin "v${VERSION}" --force

# Create GitHub Release with DMG attached.
RELEASE_NOTES_ARG=()
if [[ -n "${NOTES_FILE}" && -f "${NOTES_FILE}" ]]; then
  RELEASE_NOTES_ARG=(--notes-file "${NOTES_FILE}")
else
  RELEASE_NOTES_ARG=(--notes "Verze ${VERSION}")
fi

gh release create "v${VERSION}" \
  --title "Locute ${VERSION}" \
  "${RELEASE_NOTES_ARG[@]}" \
  "${VERSIONED_DMG}"

echo ""
echo "Released v${VERSION}."
echo "  DMG:      ${VERSIONED_DMG}"
echo "  Download: ${DOWNLOAD_URL}"
echo "  Appcast:  https://raw.githubusercontent.com/Zdenctorm/locute/main/appcast.xml"
