#!/usr/bin/env bash
# Render docs/*.png from the HTML sources in this directory.
# Requires a Chromium/Chrome binary (override with CHROMIUM=/path/to/chromium).
set -euo pipefail

cd "$(dirname "$0")"

# Prefer a headless-shell build: regular Chromium subtracts window chrome from
# --window-size even in headless mode, clipping the bottom of the page.
find_chromium() {
  local hs
  hs=$(find /opt/pw-browsers -maxdepth 3 -type f \( -name headless_shell -o -name chrome-headless-shell \) 2>/dev/null | head -1)
  if [ -n "$hs" ]; then echo "$hs"; return; fi
  command -v chrome-headless-shell || command -v chromium || command -v chromium-browser || command -v google-chrome || echo /opt/pw-browsers/chromium
}
CHROMIUM="${CHROMIUM:-$(find_chromium)}"

render() {
  local name="$1" size="$2"
  "$CHROMIUM" --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="$size" \
    --screenshot="../$name.png" "file://$PWD/$name.html" 2>/dev/null
  echo "rendered ../$name.png ($size)"
}

render architecture 960,560
render before-after 960,400
render before-after-human 960,440
