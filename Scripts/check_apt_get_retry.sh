#!/usr/bin/env sh

set -eu

# Self-test for Scripts/apt_get_retry.sh.
#
# The wrapper exists so a stalled apt mirror cannot hang a lane until its job
# cap — on 2026-08-19 `Linux repo gate (amd64)` burned its full 45 minutes on a
# single wedged `InRelease` fetch and reported as a broken repo gate. The
# guarantee that matters is therefore the stalled-mirror case below: with the
# timeout(1) wrapper removed from apt_get_retry.sh it blocks for the fake apt's
# full sleep, so the elapsed-time assertion fails and the check cannot pass
# vacuously against a neutered wrapper.
#
# Everything runs against a fake apt-get with backoff disabled, so this
# completes in seconds and needs neither sudo nor network.

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
wrapper="$repo_root/Scripts/apt_get_retry.sh"

tmpdir="${TMPDIR:-/tmp}/swifttui-apt-get-retry.$$"
mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

fake_apt="$tmpdir/fake-apt-get"
attempts_file="$tmpdir/attempts"
argv_file="$tmpdir/argv"

# A fake apt-get driven by two knobs: FAKE_APT_FAIL_TIMES failures (exit
# FAKE_APT_EXIT) before it starts succeeding, and FAKE_APT_SLEEP_SECONDS to
# emulate the stalled-mirror hang.
cat >"$fake_apt" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$@" >"$FAKE_APT_ARGV"
count=$(cat "$FAKE_APT_ATTEMPTS" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s' "$count" >"$FAKE_APT_ATTEMPTS"
if [ "${FAKE_APT_SLEEP_SECONDS:-0}" -gt 0 ]; then
  sleep "$FAKE_APT_SLEEP_SECONDS"
fi
if [ "$count" -le "${FAKE_APT_FAIL_TIMES:-0}" ]; then
  exit "${FAKE_APT_EXIT:-1}"
fi
exit 0
EOF
chmod +x "$fake_apt"

failures=0

fail() {
  >&2 echo "FAIL: $*"
  failures=$((failures + 1))
}

# Runs the wrapper against the fake apt-get with a clean attempt counter, and
# writes its exit status to $tmpdir/status. Never aborts the check.
run_wrapper() {
  fail_times=$1
  exit_code=$2
  sleep_seconds=$3
  timeout_seconds=$4
  attempts=$5
  shift 5

  : >"$attempts_file"
  set +e
  FAKE_APT_ARGV="$argv_file" \
    FAKE_APT_ATTEMPTS="$attempts_file" \
    FAKE_APT_FAIL_TIMES="$fail_times" \
    FAKE_APT_EXIT="$exit_code" \
    FAKE_APT_SLEEP_SECONDS="$sleep_seconds" \
    APT_GET_RETRY_APT_BIN="$fake_apt" \
    APT_GET_RETRY_SUDO_BIN="" \
    APT_GET_RETRY_BACKOFF_SECONDS=0 \
    APT_GET_RETRY_ATTEMPTS="$attempts" \
    APT_GET_RETRY_TIMEOUT_SECONDS="$timeout_seconds" \
    "$wrapper" "$@" >"$tmpdir/stdout" 2>"$tmpdir/stderr"
  printf '%s' "$?" >"$tmpdir/status"
  set -e
}

wrapper_status() { cat "$tmpdir/status"; }
recorded_attempts() { cat "$attempts_file" 2>/dev/null || echo 0; }

# --- a call that succeeds first time is not retried -------------------------
run_wrapper 0 0 0 30 3 update
[ "$(wrapper_status)" = "0" ] ||
  fail "clean update exited $(wrapper_status), expected 0"
[ "$(recorded_attempts)" = "1" ] ||
  fail "clean update ran $(recorded_attempts) attempt(s), expected 1"

# --- the caller's arguments survive, and the Acquire bounds are added -------
for key in \
  "Acquire::Retries=3" \
  "Acquire::http::Timeout=30" \
  "Acquire::https::Timeout=30"; do
  grep -qxF "$key" "$argv_file" ||
    fail "apt-get invocation is missing '$key'; a stalled fetch would be unbounded"
done
grep -qxF "update" "$argv_file" ||
  fail "apt-get invocation dropped the 'update' subcommand"

run_wrapper 0 0 0 30 3 install -y --no-install-recommends curl git
[ "$(wrapper_status)" = "0" ] ||
  fail "install exited $(wrapper_status), expected 0"
install_line=$(grep -n -x -- "install" "$argv_file" | cut -d: -f1)
curl_line=$(grep -n -x -- "curl" "$argv_file" | cut -d: -f1)
[ "$install_line" -lt "$curl_line" ] ||
  fail "install subcommand did not precede its package arguments"
grep -qxF -- "--no-install-recommends" "$argv_file" ||
  fail "install invocation dropped --no-install-recommends"

# --- a transient failure is retried and then succeeds -----------------------
run_wrapper 2 100 0 30 3 update
[ "$(wrapper_status)" = "0" ] ||
  fail "transient failure exited $(wrapper_status), expected 0 after retries"
[ "$(recorded_attempts)" = "3" ] ||
  fail "transient failure ran $(recorded_attempts) attempt(s), expected 3"

# --- a persistent failure exhausts attempts and surfaces apt's exit code ----
run_wrapper 99 100 0 30 3 update
[ "$(wrapper_status)" = "100" ] ||
  fail "persistent failure exited $(wrapper_status), expected apt's 100"
[ "$(recorded_attempts)" = "3" ] ||
  fail "persistent failure ran $(recorded_attempts) attempt(s), expected 3"

# --- THE GUARANTEE: a stalled apt is killed, reported, and retried ----------
# Without timeout(1) in the wrapper this blocks 60s per attempt and the elapsed
# assertion fails, so the case cannot pass against a neutered wrapper.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  started=$(date +%s)
  run_wrapper 0 0 60 1 2 update
  elapsed=$(($(date +%s) - started))

  [ "$(wrapper_status)" != "0" ] || fail "a stalled apt-get reported success"
  [ "$(wrapper_status)" = "124" ] ||
    fail "stalled apt-get exited $(wrapper_status), expected timeout(1)'s 124"
  [ "$elapsed" -lt 30 ] ||
    fail "stalled apt-get took ${elapsed}s to give up; the timeout ceiling is not applied"
  [ "$(recorded_attempts)" = "2" ] ||
    fail "stalled apt-get ran $(recorded_attempts) attempt(s), expected 2"
  grep -q "stalled mirror" "$tmpdir/stderr" ||
    fail "a stalled apt-get did not name the stall in its diagnostic"
else
  >&2 echo "note: no timeout(1) available; skipped the stall-ceiling case"
fi

# --- misuse is rejected rather than silently passed through -----------------
check_usage_error() {
  description=$1
  shift
  set +e
  env "$@" APT_GET_RETRY_APT_BIN="$fake_apt" APT_GET_RETRY_SUDO_BIN="" \
    "$wrapper" ${usage_args:-} >/dev/null 2>&1
  usage_status=$?
  set -e
  [ "$usage_status" -eq 2 ] ||
    fail "$description exited $usage_status, expected 2"
}

usage_args=""
check_usage_error "no-argument invocation"
usage_args="update"
check_usage_error "APT_GET_RETRY_ATTEMPTS=0" APT_GET_RETRY_ATTEMPTS=0
check_usage_error "a non-numeric timeout" APT_GET_RETRY_TIMEOUT_SECONDS=soon

if [ "$failures" -ne 0 ]; then
  >&2 echo "check_apt_get_retry: $failures assertion(s) failed"
  exit 1
fi

echo "check_apt_get_retry: OK"
