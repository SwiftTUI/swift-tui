#!/usr/bin/env sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

failures=0

fail() {
  failures=$((failures + 1))
  >&2 echo "error: $1"
}

if rg -n \
  "childPlacements|placeStackChildren|placeLazyStackChildren|placeIndexedLazyStackChildren|placeLayoutDependentContent" \
  Sources/SwiftTUICore/Measure Sources/SwiftTUICore/Place; then
  fail "removed recursive placement helper names are present in layout sources"
fi

if rg -n "pthread_attr_setstacksize|pthread_create|pthread_join|stackSize = 8 \\* 1024 \\* 1024" \
  Sources/SwiftTUIRuntime/Rendering/FrameTailLayoutWorker.swift; then
  fail "FrameTailLayoutWorker reintroduced Darwin pthread or manual stack sizing"
fi

if [ ! -f Sources/SwiftTUICore/Measure/LayoutEngine+MeasurementWorkStack.swift ]; then
  fail "missing explicit measurement work-stack implementation"
fi

if [ ! -f Sources/SwiftTUICore/Place/LayoutEngine+PlacementWorkStack.swift ]; then
  fail "missing explicit placement work-stack implementation"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "Layout work-stack guardrails passed."
