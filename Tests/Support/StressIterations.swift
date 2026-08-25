#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif canImport(ucrt)
import CRT
#endif

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
@_spi(Testing) public var stressFullLaneRequested: Bool {
  guard let raw = unsafe getenv("SWIFTTUI_STRESS_FULL") else { return false }
  return unsafe String(cString: raw) == "1"
}
