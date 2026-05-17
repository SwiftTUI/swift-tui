#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
targets_file="$repo_root/Scripts/lib/public_docc_targets.txt"
spi_manifest="$repo_root/.spi.yml"
missing=0

fail() {
  >&2 echo "ERROR: $1"
  missing=1
}

if [ ! -f "$targets_file" ]; then
  >&2 echo "ERROR: Missing DocC target manifest: $targets_file"
  exit 1
fi

declared_products=$(
  sed -n 's/.*\.library(name: "\([^"]*\)".*/\1/p' "$repo_root/Package.swift" | sort -u
)

declared_targets=$(
  awk -F '|' '
    /^[[:space:]]*($|#)/ { next }
    { print $1 }
  ' "$targets_file" | sort -u
)

products_file=$(mktemp)
targets_only_file=$(mktemp)
spi_targets_file=$(mktemp)
trap 'rm -f "$products_file" "$targets_only_file" "$spi_targets_file"' EXIT

printf '%s\n' "$declared_products" >"$products_file"
printf '%s\n' "$declared_targets" >"$targets_only_file"

not_in_manifest=$(comm -23 "$products_file" "$targets_only_file")
if [ -n "$not_in_manifest" ]; then
  fail "Root package product(s) missing from Scripts/lib/public_docc_targets.txt: $(printf '%s' "$not_in_manifest" | paste -sd ', ' -)"
fi

if [ ! -f "$spi_manifest" ]; then
  fail "Missing Swift Package Index manifest: .spi.yml"
else
  if ! rg -n --fixed-strings --quiet -- 'version: 1' "$spi_manifest"; then
    fail ".spi.yml must declare Swift Package Index manifest version 1"
  fi

  if ! rg -n --fixed-strings --quiet -- 'documentation_targets:' "$spi_manifest"; then
    fail ".spi.yml must configure documentation_targets for Swift Package Index-hosted DocC"
  fi

  spi_targets=$(
    awk '
      /^[[:space:]]*(-[[:space:]]*)?documentation_targets:[[:space:]]*$/ {
        in_targets = 1
        next
      }
      in_targets && /^[[:space:]]*-[[:space:]]*[[:alnum:]_]+[[:space:]]*(#.*)?$/ {
        target = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", target)
        sub(/[[:space:]]*#.*/, "", target)
        gsub(/[[:space:]]/, "", target)
        print target
        next
      }
      in_targets && /^[^[:space:]]/ {
        in_targets = 0
      }
    ' "$spi_manifest"
  )

  if [ -n "$spi_targets" ]; then
    printf '%s\n' "$spi_targets" | sort -u >"$spi_targets_file"
  else
    : >"$spi_targets_file"
    fail ".spi.yml documentation_targets must use the expanded target-list form"
  fi

  missing_from_spi=$(comm -23 "$targets_only_file" "$spi_targets_file")
  if [ -n "$missing_from_spi" ]; then
    fail ".spi.yml documentation_targets missing target(s): $(printf '%s' "$missing_from_spi" | paste -sd ', ' -)"
  fi

  extra_in_spi=$(comm -13 "$targets_only_file" "$spi_targets_file")
  if [ -n "$extra_in_spi" ]; then
    fail ".spi.yml documentation_targets not listed in Scripts/lib/public_docc_targets.txt: $(printf '%s' "$extra_in_spi" | paste -sd ', ' -)"
  fi

  first_spi_target=$(printf '%s\n' "$spi_targets" | sed -n '1p')
  if [ "$first_spi_target" != "SwiftTUI" ]; then
    fail ".spi.yml should list SwiftTUI first as the hosted documentation entry point"
  fi
fi

while IFS='|' read -r target catalog; do
  case "$target" in
  '' | \#*)
    continue
    ;;
  esac

  if [ -z "$catalog" ]; then
    fail "DocC target manifest entry for $target is missing a catalog path"
    continue
  fi

  catalog_path="$repo_root/$catalog"
  index_path="$catalog_path/$target.md"

  case "$catalog" in
  Examples/*)
    fail "$target lists an example DocC catalog; examples do not require DocC coverage"
    ;;
  esac

  if [ ! -d "$catalog_path" ]; then
    fail "Missing DocC catalog for $target: $catalog"
    continue
  fi

  if [ ! -f "$index_path" ]; then
    fail "Missing DocC landing page for $target: $catalog/$target.md"
    continue
  fi

  if ! rg -n --fixed-strings --quiet -- "# \`\`$target\`\`" "$index_path"; then
    fail "DocC landing page for $target should start with '# \`\`$target\`\`'"
  fi
done <"$targets_file"

example_docc=$(
  find "$repo_root/Examples" \
    -path '*/.build/*' -prune -o \
    -name '*.docc' -type d -print
)
if [ -n "$example_docc" ]; then
  fail "Example apps do not need DocC catalogs; remove: $(printf '%s' "$example_docc" | sed "s#$repo_root/##" | paste -sd ', ' -)"
fi

if ! rg -n --fixed-strings --quiet -- '"build:docc": "../Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs"' "$repo_root/Website/package.json"; then
  fail "Website/package.json must expose build:docc through Scripts/build_docc_archive.sh"
fi

if ! rg -n --quiet -- '"build:full": ".*build:docc.*copy:docc' "$repo_root/Website/package.json"; then
  fail "Website/package.json build:full must generate and copy DocC output"
fi

if ! rg -n --quiet -- '"build:dev": ".*build:docc.*copy:docc' "$repo_root/Website/package.json"; then
  fail "Website/package.json build:dev must generate and copy DocC output"
fi

if ! rg -n --fixed-strings --quiet -- './Scripts/build_docc_archive.sh --hosting-base-path docs --output-path .build-docs' "$repo_root/.github/workflows/cloudflare-pages.yml"; then
  fail "Cloudflare Pages workflow must build DocC through Scripts/build_docc_archive.sh"
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "[check_docc_coverage] ok"
