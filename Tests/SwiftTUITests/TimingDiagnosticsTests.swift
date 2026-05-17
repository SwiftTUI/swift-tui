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

    #expect(artifacts.diagnostics.timing.phaseTimings != nil)
    #expect(artifacts.diagnostics.timing.workerTimings != nil)
    #expect(artifacts.diagnostics.timing.mainActorTimings?.suspended == .zero)
    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
  }
}
