import SwiftTUI

/// One member of the committed benchmark suite (plan 2026-08-11-005 D2).
public struct BenchMember: Equatable, Sendable {
  public var scenario: PerfScenarioName
  /// Warm-lane render modes, in run order. `sync` appears exactly where the
  /// member's closed-loop drive makes the warm counter census deterministic
  /// (one committed frame per awaited input); open-loop and
  /// animation-clocked members run async only.
  public var warmModes: [RuntimeRenderMode]
  /// Whether the warm `sync` lane's counters join the committed ratchet
  /// (D4: the click-driven closed-loop members only).
  public var warmSyncRatchets: Bool

  public init(
    scenario: PerfScenarioName,
    warmModes: [RuntimeRenderMode],
    warmSyncRatchets: Bool
  ) {
    self.scenario = scenario
    self.warmModes = warmModes
    self.warmSyncRatchets = warmSyncRatchets
  }
}

/// The pinned benchmark suite: a code-level list, not a doc convention, so
/// "the benchmark" is exactly what `bench` runs and an outside reader can
/// cite it by member name.
public enum BenchSuite {
  /// D2's members. `bench-deep-grid` and `bench-storm` join in Stage 2.
  public static let members: [BenchMember] = [
    BenchMember(
      scenario: .lazyVStackScroll,
      warmModes: [.async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .memoEquatableBoundary,
      warmModes: [.sync, .async],
      warmSyncRatchets: true
    ),
    BenchMember(
      scenario: .syntheticContinuousAnimation,
      warmModes: [.async],
      warmSyncRatchets: false
    ),
  ]

  public static func member(named name: PerfScenarioName) -> BenchMember? {
    members.first { $0.scenario == name }
  }
}
