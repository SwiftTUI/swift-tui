#!/usr/bin/env sh

# DocC coverage check.
#
# Property: every `.library` product declared in Package.swift ships a DocC
# catalog, so the published reference stays complete.
#
# This check is convention-based and keeps no hand-maintained manifest. The
# DocC catalog for a target is, by repo convention, a directory named
# `<target>.docc` somewhere under Sources/ or Platforms/. The check derives the
# expected set of products straight from Package.swift and confirms each one's
# catalog exists.
#
# Scripts/lib/public_docc_targets.txt still drives Scripts/build_docc_archive.sh
# (it also lists package-only support targets such as SwiftTUICore); it is a
# build input, not validated here.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

products=$(
  sed -n 's/.*\.library(name: "\([^"]*\)".*/\1/p' Package.swift \
    | LC_ALL=C sort -u
)

if [ -z "$products" ]; then
  >&2 echo "[check_docc_coverage] Could not find any .library products in Package.swift."
  exit 1
fi

failures=0
for product in $products; do
  catalog=$(
    find Sources Platforms -type d -name "$product.docc" -print 2>/dev/null \
      | head -n 1
  )
  if [ -z "$catalog" ]; then
    >&2 echo "[check_docc_coverage] library product '$product' has no DocC catalog" \
      "(expected a directory named '$product.docc' under Sources/ or Platforms/)."
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  >&2 echo ""
  >&2 echo "Every .library product in Package.swift must ship a DocC catalog so the" \
    "published reference stays complete. Add the missing '<target>.docc' catalog."
  exit 1
fi

echo "[check_docc_coverage] ok — all $(printf '%s\n' "$products" | grep -c .) library products have a DocC catalog."
