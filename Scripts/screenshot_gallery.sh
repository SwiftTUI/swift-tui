#!/usr/bin/env bash
#
# Capture a screenshot of the gallery demo running in kitty.app, with the
# gallery starting on a chosen tab via the GALLERY_INITIAL_TAB env var.
#
# Usage:
#   Scripts/screenshot_gallery.sh <output.png> [tab-name]
#
# Environment:
#   SCREENSHOT_TAB     Same as positional [tab-name]; defaults to "counter".
#                      Recognised: counter, todo, calculator, borders,
#                      images, animations, files, physics.
#   SCREENSHOT_DELAY   Seconds to wait after kitty launches before
#                      capturing. Default: 2.
#
# Requirements: kitty (Homebrew), macOS screencapture, osascript. The
# script needs Screen Recording and Accessibility permissions for the
# terminal session driving it.
#
# Exit codes: 0 on success; non-zero if kitty failed to launch or the
# gallery binary is missing. The kitty window is always torn down before
# the script returns.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <output.png> [tab-name]" >&2
  exit 64
fi

out="$1"
tab="${2:-${SCREENSHOT_TAB:-counter}}"
delay="${SCREENSHOT_DELAY:-2}"

repo_root=$(cd -- "$(dirname "$0")/.." && pwd)
gallery="$repo_root/Examples/gallery/.build/arm64-apple-macosx/debug/gallery-demo"

if [[ ! -x "$gallery" ]]; then
  echo "gallery-demo not built. Run:" >&2
  echo "  swiftly run swift build --package-path $repo_root/Examples/gallery --product gallery-demo" >&2
  exit 69
fi

kitty_bin=${KITTY:-/opt/homebrew/bin/kitty}
if [[ ! -x "$kitty_bin" ]]; then
  echo "kitty not found at $kitty_bin (override with KITTY=...)" >&2
  exit 69
fi

GALLERY_INITIAL_TAB="$tab" "$kitty_bin" \
  --override remember_window_size=no \
  --override initial_window_width=1200 \
  --override initial_window_height=720 \
  -e "$gallery" >/dev/null 2>&1 &
kpid=$!

cleanup() {
  kill "$kpid" 2>/dev/null || true
  wait "$kpid" 2>/dev/null || true
}
trap cleanup EXIT

sleep "$delay"

bounds=$(osascript <<'OSA'
tell application "System Events"
  tell process "kitty"
    if (count of windows) > 0 then
      set w to front window
      set p to position of w
      set s to size of w
      return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
    else
      return "0,0,0,0"
    end if
  end tell
end tell
OSA
)

IFS=',' read -r x y w h <<< "$bounds"
if [[ "$w" == "0" || "$h" == "0" ]]; then
  echo "could not locate kitty window (System Events returned $bounds)" >&2
  exit 75
fi

/usr/sbin/screencapture -x -R "${x},${y},${w},${h}" "$out"
echo "tab=$tab bounds=$bounds wrote=$out"
