import Foundation
import Testing

@testable import TermUIPerf

struct RetainedValidationCounterTests {
  @Test("validation columns preserve disabled and legacy absence and sum every diagnostic frame")
  func roundTripAndReduction() throws {
    let names = [
      "validation_measurement_nodes",
      "validation_placement_nodes",
      "validation_environment_snapshots",
      "validation_environment_shared_storage",
      "validation_environment_values",
      "validation_identity_nodes",
      "validation_measured_restamps",
      "validation_allocation_restamps",
      "validation_placed_restamps",
      "validation_measured_equality_nodes",
      "validation_viewport_nodes",
    ]
    let header = (["frame"] + names).joined(separator: "\t")
    let values = Array(1...names.count)
    let row = (["1"] + values.map(String.init)).joined(separator: "\t")
    let disabled = (["2"] + names.map { _ in "-" }).joined(separator: "\t")
    let third = (["3"] + values.map(String.init)).joined(separator: "\t")
    let records = try PerfFrameDiagnosticsTSVReader.parse(
      [header, row, disabled, third]
        .joined(separator: "\n"))
    #expect(records[1].workCounters == PerfFrameWorkCounters())
    let total = PerfDeterministicCounters.reduce(frames: records, committedFrameCount: 1)
    for (index, name) in names.enumerated() {
      #expect(total.valuesByName[name] == (index + 1) * 2)
    }
    let encoded = try JSONEncoder().encode(total)
    #expect(try JSONDecoder().decode(PerfDeterministicCounters.self, from: encoded) == total)
    let legacy = try PerfFrameDiagnosticsTSVReader.parse("frame\n1")
    let oldTotal = PerfDeterministicCounters.reduce(frames: legacy, committedFrameCount: 1)
    #expect(names.allSatisfy { oldTotal.valuesByName[$0] == nil })
    #expect(Set(names).isDisjoint(with: BenchRatchet.warmRatchetCounters))
  }
}
