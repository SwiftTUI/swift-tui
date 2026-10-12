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
  /// Whether the cold lane collects text paint-loop visits for this member.
  ///
  /// Defaults to disabled. Enable it for workloads whose baseline should pin text
  /// traversal (i.e. text clipping); most members and warm lanes do not record text line visits.
  public var recordsTextLineVisits: Bool

  public init(
    scenario: PerfScenarioName,
    warmModes: [RuntimeRenderMode],
    warmSyncRatchets: Bool,
    recordsTextLineVisits: Bool = false
  ) {
    self.scenario = scenario
    self.warmModes = warmModes
    self.warmSyncRatchets = warmSyncRatchets
    self.recordsTextLineVisits = recordsTextLineVisits
  }
}

/// The pinned benchmark suite: a code-level list, not a doc convention, so
/// "the benchmark" is exactly what `bench` runs and an outside reader can
/// cite it by member name.
public enum BenchSuite {
  /// D2's original members, preview-readiness controls, and clipped-text workloads.
  ///
  /// `warmSyncRatchets` is FALSE everywhere: recording the baseline failed
  /// D3's determinism proof for the warm lanes twice, with different counter
  /// sets each time — the committed frame census varies by an idle/settle
  /// frame between identical fresh sessions, and on `bench-deep-grid` even
  /// the measure-work counters intermittently inherit that variance (an
  /// extra frame can re-measure the pressed cone). Per the D4 kill
  /// condition the warm ratchet is demoted to gated-compare-only and the
  /// ratchet is cold-lane only; the variance itself is filed as a finding.
  /// Flip a member back only after the frame-census variance is pinned.
  public static let members: [BenchMember] = [
    BenchMember(
      scenario: .textClippingPlainVisible,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .textClippingPlainTop,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .textClippingPlainMiddle,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .textClippingRichVisible,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .textClippingRichTop,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .textClippingRichMiddle,
      warmModes: [.sync],
      warmSyncRatchets: false,
      recordsTextLineVisits: true
    ),
    BenchMember(
      scenario: .benchDeepGrid,
      warmModes: [.sync, .async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .benchStorm,
      warmModes: [.async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .lazyVStackScroll,
      warmModes: [.async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .memoEquatableBoundary,
      warmModes: [.sync, .async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .syntheticContinuousAnimation,
      warmModes: [.async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .dynamicPropertyHeavy,
      warmModes: [.sync, .async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .galleryTabSwitch,
      warmModes: [.sync, .async],
      warmSyncRatchets: false
    ),
    BenchMember(
      scenario: .stillImagePresentation,
      warmModes: [.sync, .async],
      warmSyncRatchets: false
    ),
  ]

  public static func member(named name: PerfScenarioName) -> BenchMember? {
    members.first { $0.scenario == name }
  }
}
