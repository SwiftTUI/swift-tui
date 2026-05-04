import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct InteractionGateTests {
  @Test("disabled gate removes focus and interaction routes but keeps lifecycle")
  func disabledGateRemovesRoutesButKeepsLifecycle() {
    let gatedIdentity = testIdentity("Gated")
    let liveIdentity = testIdentity("Live")

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Gated")
          .focusable(true)
          .onAppear {}
          .onDisappear {}
          .task(id: "gated-task") {}
          .id(gatedIdentity)
          .interactionGate(.disabled(reason: .authorRequested))
        Text("Live")
          .focusable(true)
          .id(liveIdentity)
      },
      context: .init(identity: testIdentity("InteractionGateRoot")),
      proposal: .init(width: 20, height: 4)
    )

    let focusIdentities = artifacts.semanticSnapshot.focusRegions.map(\.identity)
    let interactionIdentities = artifacts.semanticSnapshot.interactionRegions.map(\.identity)
    let lifecycleIdentities = artifacts.commitPlan.lifecycle.map(\.identity)

    #expect(!focusIdentities.contains(gatedIdentity))
    #expect(!interactionIdentities.contains(gatedIdentity))
    #expect(focusIdentities.contains(liveIdentity))
    #expect(interactionIdentities.contains(liveIdentity))
    #expect(lifecycleIdentities.contains(gatedIdentity))
  }
}
