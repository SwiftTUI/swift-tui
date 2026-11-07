#!/usr/bin/env bash
# Build once per architecture, retaining bounded silence and hang diagnostics.
set -euo pipefail
cd "$(dirname "$0")/.."
export SWIFTTUI_WARNINGS_AS_ERRORS=1
step_timeout_seconds=600
step_timeout_kill_grace_seconds=10
step_absolute_timeout_seconds=1740
step_output_probe_ticks=25
step_busy_grace_seconds=300
step_busy_min_cpu_percent=25
step_watchdog_deadline_seconds=1800
source Scripts/lib/step_watchdog.sh
validate_timeout_configuration
mkdir -p .build
run_logged_command .build/ci-build.log .build/ci-build.status .build/ci-build.timeout \
  swiftly run swift build --build-system native --build-tests -Xswiftc -emit-loaded-module-trace
