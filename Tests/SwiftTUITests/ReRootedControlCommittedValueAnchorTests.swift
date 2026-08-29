import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A `.id(_:)`-re-rooted control keeps a STALE `parent` back-reference to the
/// generation that last committed it as a child. `replaceCommittedValueAnchors`
/// uses that back-reference as its proof that a stamped node really sits under
/// the nearest stamped ancestor of the accepted tree, so once the old
/// generation departs the test rejects and the control is projected NO
/// committed-value edge at all — even though the accepted tree does carry it.
///
/// The control then ends the frame stored, visited, present in `liveNodeIDs`,
/// owning both identity-index entries and its entity route, and reachable in
/// the committed VALUE tree — yet holding no lifetime anchor but its entity
/// home, which the F91 reachability census deliberately refuses to seed. It and
/// its whole styling island (`ButtonBody` and interiors) are reported
/// unreachable, every generation, for the life of the graph.
@MainActor
@Suite(
  "Re-rooted control committed-value anchor",
  .serialized,
  FailOnSoundnessViolationGrowth()
)
struct ReRootedControlCommittedValueAnchorTests {
  /// The fixture needs BOTH a seeding interaction and ballast. The control has
  /// to be committed under a generation that later departs — a control minted
  /// and dropped inside one frame never acquires the stale back-reference —
  /// and the departing owner has to be a minority of the live tree so the
  /// frame keeps taking the incremental reconciliation route instead of
  /// collapsing into a whole-tree rebuild that re-projects every anchor.
  ///
  /// The leak COUNTER delta is the load-bearing assertion, not the per-step
  /// census read. The island is reported on a frame inside `clickText`'s own
  /// settle, and the graph re-anchors the control before control returns, so a
  /// `debugTeardownCoherenceViolation()` checkpoint between interactions sees a
  /// clean graph and passes with the fix neutered (measured: the neutered
  /// fixture emits 8 `teardown-coherence-leak` trace lines while every
  /// checkpoint reads nil). `FailOnSoundnessViolationGrowth` does not cover
  /// this either — it deliberately subtracts the leak arm out of its
  /// `teardown-coherence` growth, because that arm is the lane-owned T-ratchet.
  /// The suite is `.serialized` and guarded, which is what makes reading the
  /// process-global counter across the scenario safe.
  @Test("a re-rooted control keeps a committed-value anchor across generation churn")
  func reRootedControlKeepsCommittedValueAnchorAcrossGenerationChurn() throws {
    let baselineLeaks = SoundnessProbeConfiguration.teardownCoherenceLeakCount
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReRootedControlAnchorRoot"),
      size: .init(width: 60, height: 16)
    ) {
      ReRootedControlAnchorFixture()
    }
    defer { harness.shutdown() }

    func expectNoOrphans(after step: String) {
      let violation = harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()
      #expect(
        violation == nil,
        """
        \(step) stranded stored node(s): \(violation?.detail ?? "")
        """
      )
    }

    for generation in 0..<4 {
      let clicked = try harness.clickText("Row Button")
      #expect(clicked.contains("total \(generation + 1)"))
      expectNoOrphans(after: "clicking the control in generation \(generation)")

      let rebuilt = try harness.clickText("Bump Generation")
      #expect(rebuilt.contains("generation \(generation + 1)"))
      expectNoOrphans(after: "bumping to generation \(generation + 1)")
    }

    let leaks = SoundnessProbeConfiguration.teardownCoherenceLeakCount - baselineLeaks
    #expect(
      leaks == 0,
      """
      re-rooted control stranded its island on \(leaks) sampled frame(s): \
      \(SoundnessProbeConfiguration.lastViolationDetail ?? "no detail recorded")
      """
    )
  }
}

private struct ReRootedControlAnchorFixture: View {
  @State private var generation = 0
  @State private var total = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Bump Generation") { generation += 1 }
      Text("generation \(generation) total \(total)")
      ForEach(0..<4, id: \.self) { index in
        Text("ballast \(index)")
      }
      ReRootedControlAnchorOwner(total: $total)
        .id(testIdentity("ReRootedControlAnchor", "owner", "\(generation)"))
    }
    .frame(width: 60, height: 16, alignment: .topLeading)
  }
}

private struct ReRootedControlAnchorOwner: View {
  @Binding var total: Int

  var body: some View {
    ForEach(0..<1, id: \.self) { _ in
      Button("Row Button") { total += 1 }
        .id(testIdentity("ReRootedControlAnchor", "control"))
    }
  }
}
