import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct RenderDriverInstrumentationCostTests {
  @Test("Rendering without reading diagnostics does not walk diagnostic trees")
  func diagnosticsAreLazy() {
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(
      VStack {
        Text("a")
        Text("b")
      },
      context: .init(identity: testIdentity("DiagnosticsLazyRoot")))

    _ = artifacts.rasterSurface

    #expect(
      FrameDiagnostics.debugSummaryComputationCount() == 0,
      "diagnostics summary was computed despite no diagnostics consumer")
  }

  @Test("Reading diagnostics computes the summary exactly once")
  func diagnosticsComputedOnceWhenRead() {
    FrameDiagnostics.debugResetSummaryComputationCount()
    let renderer = DefaultRenderer()
    let artifacts = renderer.render(
      VStack {
        Text("a")
        Text("b")
      },
      context: .init(identity: testIdentity("DiagnosticsReadRoot")))

    _ = artifacts.diagnostics.counts.resolvedNodes
    _ = artifacts.diagnostics.counts.resolvedNodes

    #expect(FrameDiagnostics.debugSummaryComputationCount() == 1)
  }
}
