#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
default_web_checkout="${repo_root}/../swift-tui-web"

exec "$repo_root/Scripts/update_webhost_bundle.sh" --web-checkout "$default_web_checkout"
