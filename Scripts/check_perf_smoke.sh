#!/bin/sh
set -eu

script_root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/swifttui-perf-smoke-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin"
cat > "$work/bin/swiftly" <<'STUB'
#!/bin/sh
case "$*" in
  *gallery-animation-click*)
    [ "$CASE" != primary-failure ] || exit 17
    [ "$CASE" != missing-artifacts ] || exit 0
    mkdir -p .perf/runs/base .perf/runs/candidate
    printf '{}\n' > .perf/runs/base/summary.json
    printf '{}\n' > .perf/runs/candidate/summary.json
    printf '.perf/runs/base\n.perf/runs/candidate\n'
    ;;
  *compare*) [ "$CASE" != compare-failure ] || exit 23 ;;
  *) [ "$CASE" != advisory-failure ] || exit 9 ;;
esac
STUB
chmod +x "$work/bin/swiftly"
for test_case in success primary-failure missing-artifacts compare-failure advisory-failure; do
  mkdir "$work/$test_case"
  status=0
  (cd "$work/$test_case" && CASE="$test_case" PATH="$work/bin:$PATH" sh "$script_root/run_perf_smoke.sh") \
    > "$work/$test_case.log" 2>&1 || status=$?
  case "$test_case" in
    success|advisory-failure) expected=0 ;;
    primary-failure) expected=17 ;;
    compare-failure) expected=23 ;;
    missing-artifacts) expected=1 ;;
  esac
  if [ "$status" -ne "$expected" ]; then
    cat "$work/$test_case.log" >&2
    echo "error: $test_case expected exit $expected, got $status" >&2
    exit 1
  fi
done
grep -q 'FAILED(9)' "$work/advisory-failure/.perf/runs/scroll-advisory-status.txt"
echo 'perf-smoke self-test: 5 cases passed'
