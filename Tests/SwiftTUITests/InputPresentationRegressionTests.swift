import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct InputPresentationRegressionTests {
  @Test("modal suppression survives an inner gate disabling and enabling", arguments: [false, true])
  func modalGateCurrency(selective: Bool) throws {
    let probe = ModalGateProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModalGateCurrency"), size: .init(width: 70, height: 20),
      selectiveEvaluation: selective
    ) { ModalGateRoot(probe: probe) }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "Base action"))
    _ = try harness.clickText("Open modal")
    for disabled in [true, false, true, false] {
      probe.setDisabled?(disabled)
      _ = try harness.render()
      #expect(!harness.runLoop.latestSemanticSnapshot.focusRegions.contains {
        $0.identity == testIdentity("GatedBaseAction")
      })
      _ = try harness.click(point)
      #expect(probe.actions == 0)
      #expect(harness.frame.contains("Close modal"))
    }
    _ = try harness.clickText("Close modal")
    _ = try harness.clickText("Base action")
    #expect(probe.actions == 1)
  }

  @Test("a parent modal reason overrides an authored disabled reason")
  func modalReasonWins() {
    let base = SemanticMetadata(interactionAvailability: .disabled(reason: .authorRequested))
    let modal = SemanticMetadata(interactionAvailability: .disabled(reason: .modalOverlay))
    #expect(base.merging(modal).interactionAvailability == .disabled(reason: .modalOverlay))
    #expect(modal.merging(SemanticMetadata()).interactionAvailability == .disabled(reason: .modalOverlay))
  }
}

@MainActor
private final class ModalGateProbe {
  var actions = 0
  var setDisabled: ((Bool) -> Void)?
}

private struct ModalGateRoot: View {
  let probe: ModalGateProbe
  @State private var presented = false
  var body: some View {
    VStack(alignment: .leading) {
      ModalGateBase(probe: probe)
      Button("Open modal") { presented = true }
      Spacer()
    }
    .sheet("Gate test", isPresented: $presented) {
      Button("Close modal") { presented = false }
    }
  }
}

private struct ModalGateBase: View {
  let probe: ModalGateProbe
  @State private var disabled = false
  var body: some View {
    Button("Base action") { probe.actions += 1 }
      .id(testIdentity("GatedBaseAction"))
      .interactionGate(disabled ? .disabled(reason: .authorRequested) : .enabled)
      .onAppear { probe.setDisabled = { disabled = $0 } }
  }
}
