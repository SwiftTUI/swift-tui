import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The duplicate-slot-claim diagnostic's window must open at the dynamic-
/// property update pass, not at `beginEvaluation`: the update pass records a
/// container's claims BEFORE the reuse door, and a reuse-served resolve never
/// reaches `beginEvaluation`'s reset. A child whose update pass claimed and
/// was then served from the memo layer left that claim behind; the next
/// evaluation's (legitimately new) box collided with it and reported phantom
/// sharing on ScrollView / TimelineView / popover-tip state in the gallery.
@MainActor
@Suite
struct StateSlotClaimWindowTests {
  @Test("a reuse-served update pass leaves no stale slot claim for the next evaluation")
  func reuseServedUpdatePassLeavesNoStaleClaim() {
    let renderer = DefaultRenderer()
    let root = testIdentity("ClaimWindowRoot")
    // Built up front and kept alive for the whole test: each copy owns a
    // distinct `@State` box, and a box freed between renders could hand its
    // address to the next allocation — masking a collision behind an
    // `ObjectIdentifier` that merely LOOKS like the same claimant.
    let hosts = (1...3).map { ClaimWindowHost(tick: $0) }

    func render(tick: Int) -> RenderSnapshot {
      renderer.render(
        hosts[tick - 1],
        context: .init(
          identity: root,
          invalidatedIdentities: tick == 1 ? [] : [root]
        )
      )
    }
    func duplicateClaims(_ snapshot: RenderSnapshot) -> [RuntimeIssue] {
      snapshot.diagnostics.runtime.issues.filter { $0.code == "state.duplicateSlotClaim" }
    }

    let first = render(tick: 1)
    #expect(duplicateClaims(first).isEmpty)

    // The host re-runs; the child is value-equal and read-free, so the memo
    // layer serves it AFTER its update pass recorded this copy's claim.
    let second = render(tick: 2)
    #expect(
      second.diagnostics.work.resolvedNodesReused > 0,
      "precondition: the child must be reuse-served on the second render"
    )
    #expect(duplicateClaims(second).isEmpty)

    // The host re-runs again with a fresh child copy: its update pass claims
    // the same slot with a new box. That is one container per evaluation, not
    // two wrappers sharing storage — no diagnostic.
    let third = render(tick: 3)
    #expect(
      duplicateClaims(third).isEmpty,
      "a served update pass's claim leaked into the next evaluation: \(duplicateClaims(third))"
    )
  }
}

private struct ClaimWindowChild: View {
  /// Never read, so the node records no state dependency and stays
  /// memo-servable under a re-run ancestor.
  @State private var unread = 0
  let label: String

  var body: some View {
    Text(label)
  }
}

private struct ClaimWindowHost: View {
  let tick: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("tick \(tick)")
      ClaimWindowChild(label: "stable")
    }
  }
}
