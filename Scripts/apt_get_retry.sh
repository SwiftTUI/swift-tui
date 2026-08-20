#!/usr/bin/env sh

set -eu

# Bounded, retrying `apt-get` for the CI lanes.
#
# apt applies no network timeout by default. When a mirror completes the TCP
# handshake and then stalls mid-transfer, `apt-get update` blocks forever and
# the step emits no further output — indistinguishable, from the outside, from
# a slow download. On 2026-08-19 that wedged `Linux repo gate (amd64)` for its
# full 45m cap on the fetch of `archive.ubuntu.com noble-security InRelease`,
# roughly 50 seconds into the job. The kill then failed the 2-second
# `Require native Linux matrix` aggregator, which is the check the org root
# reads — so one stalled fetch reported as a broken repo gate.
#
# Every call is bounded three ways, so a stalled mirror fails fast and loudly
# instead of hanging until the job cap:
#
#   Acquire::http[s]::Timeout   per-connection network timeout
#   Acquire::Retries            apt-internal retries within one invocation
#   timeout(1)                  hard wall-clock ceiling on the whole call
#
# and the bounded call is then retried with linear backoff, because a mirror
# that stalls once usually serves the next attempt.
#
# Usage mirrors apt-get:
#   Scripts/apt_get_retry.sh update
#   Scripts/apt_get_retry.sh install -y --no-install-recommends curl git
#
# Knobs (env, all optional) — the defaults are the CI contract;
# Scripts/check_apt_get_retry.sh overrides them to run in seconds without sudo
# or a real apt.
#   APT_GET_RETRY_ATTEMPTS          attempts before giving up      (default 3)
#   APT_GET_RETRY_TIMEOUT_SECONDS   wall-clock ceiling per attempt (default 300)
#   APT_GET_RETRY_BACKOFF_SECONDS   backoff base; attempt N waits N*base (10)
#   APT_GET_RETRY_APT_BIN           apt-get binary               (default apt-get)
#   APT_GET_RETRY_SUDO_BIN          sudo binary; empty disables  (default sudo)

: "${APT_GET_RETRY_ATTEMPTS:=3}"
: "${APT_GET_RETRY_TIMEOUT_SECONDS:=300}"
: "${APT_GET_RETRY_BACKOFF_SECONDS:=10}"
: "${APT_GET_RETRY_APT_BIN:=apt-get}"
: "${APT_GET_RETRY_SUDO_BIN=sudo}"

if [ "$#" -eq 0 ]; then
  >&2 echo "usage: apt_get_retry.sh <apt-get-subcommand> [args...]"
  exit 2
fi

require_non_negative_integer() {
  case "$2" in
  "" | *[!0-9]*)
    >&2 echo "$1 must be a non-negative integer (got '$2')"
    exit 2
    ;;
  esac
}

require_non_negative_integer APT_GET_RETRY_ATTEMPTS "$APT_GET_RETRY_ATTEMPTS"
require_non_negative_integer APT_GET_RETRY_TIMEOUT_SECONDS "$APT_GET_RETRY_TIMEOUT_SECONDS"
require_non_negative_integer APT_GET_RETRY_BACKOFF_SECONDS "$APT_GET_RETRY_BACKOFF_SECONDS"

if [ "$APT_GET_RETRY_ATTEMPTS" -eq 0 ]; then
  >&2 echo "APT_GET_RETRY_ATTEMPTS must be at least 1"
  exit 2
fi

# `timeout` is the hard backstop for the exact failure this script exists to
# prevent, so resolve it explicitly rather than silently degrading: GNU
# coreutils ships it as `timeout`, Homebrew's as `gtimeout`. If neither is
# present the Acquire timeouts still bound each connection, so we proceed
# rather than fail the lane — but we say so, because the guarantee is weaker.
timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
  timeout_bin="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_bin="gtimeout"
else
  >&2 echo "apt_get_retry: no timeout(1) found; relying on Acquire timeouts only"
fi

run_bounded_apt_get() {
  set -- \
    -o Acquire::Retries=3 \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    "$@"

  if [ -n "$APT_GET_RETRY_SUDO_BIN" ]; then
    set -- "$APT_GET_RETRY_SUDO_BIN" "$APT_GET_RETRY_APT_BIN" "$@"
  else
    set -- "$APT_GET_RETRY_APT_BIN" "$@"
  fi

  if [ -n "$timeout_bin" ]; then
    # SIGKILL after a grace period: a wedged apt child can ignore SIGTERM, and
    # a watchdog that can itself hang is not a watchdog.
    set -- "$timeout_bin" --kill-after=30s "${APT_GET_RETRY_TIMEOUT_SECONDS}s" "$@"
  fi

  "$@"
}

attempt=1
while :; do
  # Capture the status directly rather than reading `$?` after an `if` block:
  # a bare `if cmd; then ... fi` reports the *statement's* status (0) once no
  # branch runs, which would swallow every apt failure as a success.
  status=0
  run_bounded_apt_get "$@" || status=$?

  if [ "$status" -eq 0 ]; then
    exit 0
  fi

  if [ "$attempt" -ge "$APT_GET_RETRY_ATTEMPTS" ]; then
    >&2 echo "apt_get_retry: '$*' failed after $attempt attempt(s) (exit $status)"
    exit "$status"
  fi

  # 124 is timeout(1)'s "deadline expired" — the stall signature. Name it, so a
  # future reader of a red log does not have to rediscover this whole story.
  if [ "$status" -eq 124 ]; then
    >&2 echo "apt_get_retry: '$*' exceeded ${APT_GET_RETRY_TIMEOUT_SECONDS}s (stalled mirror)"
  fi

  backoff=$((attempt * APT_GET_RETRY_BACKOFF_SECONDS))
  >&2 echo "apt_get_retry: attempt $attempt/$APT_GET_RETRY_ATTEMPTS failed (exit $status); retrying in ${backoff}s"
  if [ "$backoff" -gt 0 ]; then
    sleep "$backoff"
  fi
  attempt=$((attempt + 1))
done
