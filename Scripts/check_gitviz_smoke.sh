#!/usr/bin/env sh
#
# Visual smoke check for swift-tui-examples/gitviz against this repository.
# Not a CI gate — failures are visual, not asserted. Use this before commits
# to confirm the README screenshots still look like what `gitviz` produces.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
examples_root="${SWIFTTUI_EXAMPLES_CHECKOUT:-"$repo_root/../swift-tui-examples"}"
example_root="$examples_root/gitviz"
binary="$example_root/.build/debug/gitviz"

cd "$example_root"

if ! command -v swiftly >/dev/null 2>&1; then
  echo "Missing required command: swiftly" >&2
  exit 1
fi

if [ ! -x "$binary" ]; then
  echo "==> Building gitviz"
  swiftly run swift build
fi

run() {
  echo
  echo "================================================================"
  echo "$ gitviz $*"
  echo "================================================================"
  "$binary" "$@" --path "$repo_root" --no-color --width 100 --max-commits 500
}

run info
run activity --year "$(date +%Y)"
run cadence
run deltas
run loc
run kinds
run kinds-share --quarters 4
run volatility --top 8
run dag --max 10
run releases
run pulse
run recent-vs-all --top 5
run health
run concentration --top 5

echo
echo "==> done. Visually inspect output above."
