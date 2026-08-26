import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime pins for trigger-mode `PhaseAnimator` (plan 2026-08-25-003 P1),
/// driven through a real `RunLoop` so the `.task(id:)` driver, the dormant-tab
/// archive, and the controller all take part.
@MainActor
@Suite(.serialized)
struct PhaseAnimatorRuntimeTests {
  private static let bumpLabel = "bump"

  @Test("trigger mode does not animate on mount")
  func triggerModeIsQuietOnMount() async throws {
    let probe = PhaseProbe()
    let harness = try AnimatorRuntimeHarness {
      PhaseTriggerFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try await harness.hold(for: .milliseconds(300))
    #expect(Set(probe.phases) == [.rest], "\(probe.phases)")
  }

  @Test("one trigger change walks the phases once and returns to rest")
  func oneTriggerRunsOneCycle() async throws {
    let probe = PhaseProbe()
    let harness = try AnimatorRuntimeHarness {
      PhaseTriggerFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.completedCycles == 1 })
    try await harness.hold(for: .milliseconds(300))
    #expect(probe.distinctRun == [.rest, .grow, .shrink, .rest], "\(probe.distinctRun)")
  }

  // MARK: - Tabs

  @Test("leaving a tab and returning with an unchanged trigger does not replay the cycle")
  func tabReturnWithUnchangedTriggerDoesNotReplay() async throws {
    let probe = PhaseProbe()
    let harness = try AnimatorRuntimeHarness(size: .init(width: 60, height: 10)) {
      PhaseTabFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.completedCycles == 1 })

    try harness.clickText("PlainTab")
    #expect(harness.frame.contains("plain-pane"))
    let countAtSwitch = probe.phases.count
    try await harness.hold(for: .milliseconds(200))

    try harness.clickText("AnimTab")
    try await harness.hold(for: .milliseconds(700))
    let afterReturn = Array(probe.phases.dropFirst(countAtSwitch))
    #expect(
      afterReturn.allSatisfy { $0 == .rest },
      "returning to the tab replayed the phase cycle: \(afterReturn)"
    )
    #expect(probe.completedCycles == 1)
  }

  @Test("a trigger changed while the tab was dormant runs exactly one cycle on return")
  func triggerChangedWhileDormantRunsOnceOnReturn() async throws {
    let probe = PhaseProbe()
    let harness = try AnimatorRuntimeHarness(size: .init(width: 60, height: 10)) {
      PhaseTabFixture(probe: probe)
    }
    defer { harness.shutdown() }

    try harness.clickText(Self.bumpLabel)
    try await harness.wait(until: { probe.completedCycles == 1 })

    try harness.clickText("PlainTab")
    #expect(harness.frame.contains("plain-pane"))
    let countAtSwitch = probe.phases.count
    // The trigger lives above the tab view, so it can change while the
    // animator's tab is dormant.
    try harness.clickText(Self.bumpLabel)
    try await harness.hold(for: .milliseconds(200))
    #expect(
      probe.phases.count == countAtSwitch,
      "the animator wrote while its tab was dormant: \(probe.phases)"
    )

    try harness.clickText("AnimTab")
    try await harness.wait(until: { probe.completedCycles == 2 })
    try await harness.hold(for: .milliseconds(400))
    let afterReturn = Array(probe.phases.dropFirst(countAtSwitch))
    let cyclesAfterReturn = afterReturn.filter { $0 == .grow }.count
    #expect(probe.completedCycles == 2, "\(probe.distinctRun)")
    #expect(cyclesAfterReturn >= 1, "the changed trigger did not run on return: \(afterReturn)")
    #expect(
      PhaseProbe.distinctRun(afterReturn).filter { $0 == .grow }.count == 1,
      "more than one cycle ran on return: \(PhaseProbe.distinctRun(afterReturn))"
    )
  }
}

// MARK: - Probe

enum BouncePhase: Equatable, Sendable {
  case rest, grow, shrink
}

@MainActor
private final class PhaseProbe {
  private(set) var phases: [BouncePhase] = []

  func record(_ phase: BouncePhase) {
    phases.append(phase)
  }

  var distinctRun: [BouncePhase] { Self.distinctRun(phases) }

  static func distinctRun(_ phases: [BouncePhase]) -> [BouncePhase] {
    var run: [BouncePhase] = []
    for phase in phases where run.last != phase {
      run.append(phase)
    }
    return run
  }

  /// A cycle is complete once `.shrink` has been followed by `.rest`.
  var completedCycles: Int {
    let run = distinctRun
    return zip(run, run.dropFirst()).filter { $0 == .shrink && $1 == .rest }.count
  }
}

// MARK: - Fixtures

@MainActor
private struct PhaseTriggerFixture: View {
  let probe: PhaseProbe
  @State private var bumps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { bumps += 1 }
      PhaseAnimatorSubject(probe: probe, trigger: bumps)
    }
  }
}

@MainActor
private struct PhaseAnimatorSubject: View {
  let probe: PhaseProbe
  let trigger: Int

  var body: some View {
    PhaseAnimator([BouncePhase.rest, .grow, .shrink], trigger: trigger) { phase in
      let _ = probe.record(phase)
      Text(Self.label(for: phase))
    } animation: { _ in
      .linear(duration: .milliseconds(120))
    }
  }

  private static func label(for phase: BouncePhase) -> String {
    switch phase {
    case .rest: "rest"
    case .grow: "grow"
    case .shrink: "shrink"
    }
  }
}

@MainActor
private struct PhaseTabFixture: View {
  let probe: PhaseProbe
  @State private var selection = 0
  @State private var bumps = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { bumps += 1 }
      TabView(selection: $selection) {
        Tab("AnimTab", value: 0) {
          PhaseAnimatorSubject(probe: probe, trigger: bumps)
        }
        Tab("PlainTab", value: 1) {
          Text("plain-pane")
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}
