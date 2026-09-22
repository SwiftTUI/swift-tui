import Foundation

/// The iteration count for a churn loop in a hot-path stress test.
///
/// The repo gate's runtime shards are budgeted at ten seconds per test
/// (swift-tui-org plan 2026-08-25-001, Stage 2b; enforced by
/// `Scripts/check_test_durations.sh`). The repeated-teardown loops that used
/// to run 12–55 s on the amd64 runner read their count from here: the hot
/// path runs `hotPath` iterations, and the nightly and release-tag lanes set
/// `SWIFTTUI_STRESS_FULL=1` to run the full count. A loop that finds a defect
/// at the full count and not at the hot-path count is itself a finding worth
/// a report — the flake register has no such case yet.
///
/// - Parameters:
///   - full: the historical iteration count, kept for the full-stress lanes.
///   - hotPath: the count the push gate runs; must be in `1...full`.
@_spi(Testing) public func stressIterations(full: Int, hotPath: Int) -> Int {
  precondition(hotPath >= 1 && hotPath <= full, "hotPath must be in 1...full")
  return stressFullLaneRequested ? full : hotPath
}

/// Whether `SWIFTTUI_STRESS_FULL=1` is set for this process.
///
/// Read through Foundation rather than `getenv`: the Windows CRT deprecates
/// `getenv` (C4996) and this package builds warnings-as-errors, so a raw
/// `getenv` here is a hard Windows build failure. The framework's own
/// Foundation-free funnel (`FeatureFlags.environmentValue`) is `package`-scoped
/// to `SWIFTTUI_*` feature gates; test support already reads its knobs through
/// `ProcessInfo` (see `AsyncTestSupport.swift`), so this matches its neighbours.
@_spi(Testing) public var stressFullLaneRequested: Bool {
  ProcessInfo.processInfo.environment["SWIFTTUI_STRESS_FULL"] == "1"
}
