import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The duplicate-slot-claim diagnostic's window must open at the dynamic-
/// property update pass, not at `beginEvaluation`: the update pass records a
/// container's claims BEFORE the reuse door, and a reuse-served resolve never
/// reaches `beginEvaluation`'s reset. A child whose update pass claimed and
/// was then served from the memo layer left that claim behind; the next
/// evaluation's (legitimately new) box collided with it and reported phantom
/// sharing on ScrollView / TimelineView / popover-tip state in the gallery.
///
/// A claim can also land on a node from another node's evaluation: a wrapper
/// the update pass never discovers (a helper struct that composes `@State`
/// without conforming to `DynamicProperty`) binds when it is first read, on
/// the owner the ambient scope names. A style's `makeBody` runs under the
/// enclosing view's scope, so a control that re-resolves on its own claims on
/// that view while the view opens no window. Each claim therefore records
/// the evaluation that made it, and a record from an earlier evaluation is
/// replaced rather than reported.
@MainActor
@Suite(.serialized)
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
      snapshot.diagnostics.runtime.issues.filter { $0.typedCode == .State.duplicateSlotClaim }
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

  @Test(
    "a helper read by a control that re-resolves without its view leaves no stale claim",
    arguments: [RuntimeRenderMode.sync, .async]
  )
  func loneControlReresolveLeavesNoStaleHelperClaim(mode: RuntimeRenderMode) async throws {
    let harness = try await RuntimeIssueJourneyHarness.start(
      named: "ClaimWindowHelperRoot", mode: mode, showing: "helper page"
    ) {
      ClaimWindowHelperShell()
    }
    defer { harness.stop() }

    // Each focus move re-resolves the styled button alone. Its style builds
    // a fresh helper, whose state binds on the enclosing view.
    for _ in 0..<2 {
      try harness.click("Styled")
      try await harness.waitForScreen("the focused styled button") {
        $0.contains("Styled focused 0")
      }
      try harness.click("Plain")
      try await harness.waitForScreen("the idle styled button") {
        $0.contains("Styled idle 0")
      }
    }
    try await harness.finish()

    #expect(
      harness.duplicateSlotClaims.isEmpty,
      "one helper was reported as two sharing a slot: \(harness.duplicateSlotClaims)")
  }

  @Test("two controls whose style holds a helper still report the slot they share")
  func controlsSharingOneHelperSlotStillReport() {
    let snapshot = DefaultRenderer().render(
      ClaimWindowSharingControls(),
      context: .init(identity: testIdentity("ClaimWindowSharingControls"))
    )

    // Both helpers bind on the enclosing view, inside one evaluation of it:
    // two wrapper instances on one slot, which is what the diagnostic is for.
    #expect(
      snapshot.diagnostics.runtime.issues.contains { $0.typedCode == .State.duplicateSlotClaim },
      "two helper instances share one slot of the view that declares both controls"
    )
  }
}

/// Composes `@State` without conforming to `DynamicProperty`, so the update
/// pass never discovers it: its state binds on first read, by declaration
/// site, on the owner the ambient scope names.
@MainActor
private struct ClaimWindowHelper {
  @State var value = 0
}

private struct ClaimWindowHelperStyle: ButtonStyle {
  @MainActor
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    let helper = ClaimWindowHelper()
    return Text("Styled \(configuration.isFocused ? "focused" : "idle") \(helper.value)")
  }
}

private struct ClaimWindowHelperShell: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("helper page")
      Button("Styled") {}.buttonStyle(ClaimWindowHelperStyle())
      Button("Plain") {}
    }
  }
}

/// Holds its helper for as long as the style value lives, so two styled
/// controls of one view present two live helper instances at once. A helper
/// built inside `makeBody` is freed when the body returns, and the next one
/// can take its address and pass for the same claimant.
@MainActor
private struct ClaimWindowStoredHelperStyle: ButtonStyle {
  let helper = ClaimWindowHelper()

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Text("Stored \(helper.value)")
  }
}

private struct ClaimWindowSharingControls: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("First") {}.buttonStyle(ClaimWindowStoredHelperStyle())
      Button("Second") {}.buttonStyle(ClaimWindowStoredHelperStyle())
    }
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
