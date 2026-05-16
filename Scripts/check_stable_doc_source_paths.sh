#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
paths_file=$(mktemp)
trap 'rm -f "$paths_file"' EXIT

printf '%s\0' "$repo_root/README.md" >"$paths_file"
find "$repo_root/docs" -maxdepth 1 -name '*.md' \
  ! -name 'CHANGELOG.md' \
  -print0 >>"$paths_file"
find "$repo_root/Sources" -path '*.docc/*.md' -print0 >>"$paths_file"

if xargs -0 rg -n 'Sources/SwiftTUI/(Accessibility|Configuration|Diagnostics|Input|Lifecycle|RunLoop|Scenes|Support|Terminal|[^`[:space:]]+\.swift)' <"$paths_file"
then
  cat >&2 <<'EOF'
Stable docs still reference implementation paths that moved under
Sources/SwiftTUIRuntime/. Historical plans and proposals are intentionally not
checked by this guard.
EOF
  exit 1
fi

echo "[check_stable_doc_source_paths] ok"
