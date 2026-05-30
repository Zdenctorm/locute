#!/usr/bin/env bash
# Download competitive research assets. Run from repo root.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/screenshots"
SRC="$ROOT/sources"

dl() {
  local out="$1"
  shift
  mkdir -p "$(dirname "$out")"
  if curl -fsSL --connect-timeout 15 --max-time 120 -o "$out" "$@"; then
    local sz
    sz=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
    if [ "$sz" -gt 500 ] && file "$out" | grep -qv 'HTML document'; then
      echo "OK  $out ($sz bytes)"
      return 0
    fi
    rm -f "$out"
  fi
  echo "FAIL $out"
  return 1
}

scrape_imgs() {
  local url="$1" outdir="$2" prefix="$3"
  curl -fsSL "$url" 2>/dev/null | grep -oE 'https?://[^"'\'' <>]+\.(png|jpg|jpeg|webp|gif)(\?[^"'\'' <>]*)?' \
    | sed 's/&amp;/\&/g' | sort -u | head -40 > "$SRC/${prefix}-urls-scraped.txt" || true
}

echo "=== Whispur (GitHub) ==="
WH=https://raw.githubusercontent.com/sophiie-ai/whispur/main/docs/screenshots
for f in hero-menubar.png recording-overlay.png settings-setup.png settings-providers.png demo.gif; do
  dl "$S/whispur/$f" "$WH/$f" || true
done

echo "=== Glimpse (GitHub README assets) ==="
GL=https://raw.githubusercontent.com/LegendarySpy/Glimpse/main
for f in assets/screenshot-1.png assets/screenshot-2.png assets/screenshot-3.png \
  assets/screenshots/1.png assets/screenshots/2.png assets/screenshots/3.png \
  docs/screenshot.png docs/screenshots/hero.png; do
  dl "$S/glimpse/$(basename "$f")" "$GL/$f" 2>/dev/null || true
done
# Parse README for image paths
curl -fsSL "$GL/README.md" 2>/dev/null | grep -oE '\.(png|gif|webp|jpg)[^)]*' | head -20 > "$SRC/glimpse-readme-refs.txt" || true
curl -fsSL "$GL/README.md" 2>/dev/null | grep -oE 'assets/[^)]+' | while read -r p; do
  dl "$S/glimpse/$(basename "$p")" "$GL/$p" || true
done

echo "=== Superduper-whisper ==="
SDW=https://raw.githubusercontent.com/jhargis/superduper-whisper/main
for i in 1 2 3 4 5; do dl "$S/superduper-whisper/settings-$i.png" "$SDW/assets/screenshots/$i.png" || true; done
dl "$S/superduper-whisper/demo.gif" "$SDW/demo/demo.gif" || true

echo "=== WhisperClip ==="
WC=https://raw.githubusercontent.com/cydanix/whisperclip/main
dl "$S/whisperclip/icon-256.png" "$WC/icons/icon_256x256.png"
dl "$S/whisperclip/icon-512.png" "$WC/icons/icon_512x512.png" 2>/dev/null || true
curl -fsSL "$WC/README.md" | grep -oE 'assets/[^)]+' | while read -r p; do
  dl "$S/whisperclip/$(basename "$p")" "$WC/$p" || true
done

echo "=== Open-Wispr ==="
OW=https://github.com/user-attachments/assets
dl "$S/open-wispr/permissions-dialog.png" "$OW/9a0533ae-c174-4395-9533-46b55c3cb592"
dl "$S/open-wispr/accessibility-settings.png" "$OW/f8243e28-4fae-4aba-a030-5c4c66c3cf07"
curl -fsSL https://raw.githubusercontent.com/human37/open-wispr/main/docs/install-guide.md 2>/dev/null \
  | grep -oE 'https://github.com/user-attachments/assets/[a-f0-9-]+' | sort -u | while read -r u; do
  id=$(basename "$u")
  dl "$S/open-wispr/install-$id.png" "$u" || true
done

echo "=== Wispr Flow marketing CDN ==="
scrape_imgs "https://wisprflow.ai/" wispr wispr-flow
n=0
while read -r u; do
  n=$((n+1))
  ext="${u##*.}"; ext="${ext%%\?*}"
  dl "$S/wispr-flow/marketing-$(printf '%02d' "$n").${ext}" "$u" || true
done < "$SRC/wispr-flow-urls-scraped.txt"

dl "$S/wispr-flow/youtube-maxres.jpg" "https://i.ytimg.com/vi/x6XJIbRksgI/maxresdefault.jpg" || \
  dl "$S/wispr-flow/youtube-hq.jpg" "https://i.ytimg.com/vi/x6XJIbRksgI/hqdefault.jpg"
dl "$S/wispr-flow/youtube-demo-2.jpg" "https://i.ytimg.com/vi/PL7w0oQbcMk/hqdefault.jpg" 2>/dev/null || true

echo "=== Aqua Voice ==="
scrape_imgs "https://aquavoice.com/" aqua aqua-voice
n=0
while read -r u; do
  n=$((n+1))
  ext=png; [[ "$u" == *webp* ]] && ext=webp
  dl "$S/aqua-voice/marketing-$(printf '%02d' "$n").$ext" "$u" || true
done < "$SRC/aqua-voice-urls-scraped.txt"
dl "$S/aqua-voice/logo-1024.png" "https://app.aquavoice.com/images/logo-1024-transparent.png"

echo "=== Superwhisper ==="
dl "$S/superwhisper/og-image2x.png" "https://superwhisper.com/image/og-image2x.png"
scrape_imgs "https://superwhisper.com/" superwhisper superwhisper
n=0
while read -r u; do
  n=$((n+1))
  dl "$S/superwhisper/scraped-$(printf '%02d' "$n").png" "$u" || true
done < "$SRC/superwhisper-urls-scraped.txt" 2>/dev/null || true

echo "=== MacWhisper ==="
scrape_imgs "https://goodsnooze.com/macwhisper" macwhisper macwhisper
n=0
while read -r u; do
  n=$((n+1))
  dl "$S/macwhisper/site-$(printf '%02d' "$n").png" "$u" || true
done < "$SRC/macwhisper-urls-scraped.txt" 2>/dev/null || true
dl "$S/macwhisper/youtube-thumb.jpg" "https://i.ytimg.com/vi/0ANwyTxwS0Y/hqdefault.jpg" 2>/dev/null || true

echo "=== Vowrite (GitHub) ==="
VW=https://raw.githubusercontent.com/Beingpax/VoiceInk/main
for f in README.md; do curl -fsSL "$VW/$f" -o "$SRC/vowrite-readme.md" 2>/dev/null || true; done
# VoiceInk was renamed - try vowrite
curl -fsSL https://api.github.com/repos/Beingpax/VoiceInk/contents 2>/dev/null | head -5 || true

echo "=== Pindrop / misc YouTube thumbs ==="
dl "$S/misc/youtube-macwhisper.jpg" "https://i.ytimg.com/vi/Z8W6MGNEuF4/hqdefault.jpg" || true
dl "$S/misc/youtube-superwhisper.jpg" "https://i.ytimg.com/vi/m1AEu49VYuo/hqdefault.jpg" || true
dl "$S/misc/youtube-aqua-voice.jpg" "https://i.ytimg.com/vi/8QzXo9pqfY8/hqdefault.jpg" || true

echo "=== Move legacy flat files ==="
for f in "$S"/*-*.*; do
  [ -f "$f" ] || continue
  case "$f" in
    *wispr-flow*) mv -f "$f" "$S/wispr-flow/" ;;
    *aqua-voice*) mv -f "$f" "$S/aqua-voice/" ;;
    *whispur*) mv -f "$f" "$S/whispur/" ;;
    *open-wispr*) mv -f "$f" "$S/open-wispr/" ;;
  esac
done

echo "=== Done ==="
find "$S" -type f | wc -l
du -sh "$S" "$SRC"
