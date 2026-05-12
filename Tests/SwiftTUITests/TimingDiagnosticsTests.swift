import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TimingDiagnosticsTests {
  @Test("default renderer records per-phase timings")
  func rendererRecordsPhaseTimings() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Text("Latency")
        Text("Probe")
      },
      context: .init(identity: testIdentity("TimingRoot"))
    )

    #expect(artifacts.diagnostics.phaseTimings != nil)
    #expect(artifacts.diagnostics.workerTimings != nil)
    #expect(artifacts.diagnostics.mainActorTimings?.suspended == .zero)
    #expect(artifacts.diagnostics.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.firstCustomLayoutFallbackIdentity == nil)
  }
}
