import Testing

@testable import TerminalUI
@testable import View

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
  }
}
