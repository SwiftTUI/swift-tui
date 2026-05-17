#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

bun run Scripts/lib/check_public_documentation_ratchet.ts \
  --manifest Scripts/lib/public_documentation_ratchet.txt
