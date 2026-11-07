import Testing

@testable import TermUIPerf

@Suite(.timeLimit(.minutes(1)))
struct MetadataCaptureTests {
  @Test func capturesOutputBeyondBothPipeCapacities() {
    let chunk = String(repeating: "x", count: 64)
    let output = PerfScenarioRunner.processOutput([
      "/bin/sh", "-c",
      "i=0; while [ $i -lt 8192 ]; do printf '\(chunk)'; printf '\(chunk)' >&2; i=$((i+1)); done",
    ])
    #expect(output == String(repeating: chunk, count: 8192))
  }

  @Test func aChildIgnoringTerminationCannotStrandMetadata() {
    #expect(
      PerfScenarioRunner.processOutput(
        ["/bin/sh", "-c", "trap '' TERM; while :; do :; done"], timeout: 0.1) == nil)
  }

  @Test func failedCommandsHaveNoMetadataValue() {
    #expect(PerfScenarioRunner.processOutput(["/bin/sh", "-c", "printf partial; exit 7"]) == nil)
  }
}
