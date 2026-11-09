import Foundation
import Testing

@testable import TermUIPerf

struct DetailReuseCensusTests {
  @Test("reuse census reads only bytes appended during the current run")
  func repeatedArtifactRoot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let trace = root.appendingPathComponent("trace.log")
    let output = root.appendingPathComponent("census.json")
    try Data("[REUSE-TRACE] recompute-reasons: old=9\n".utf8).write(to: trace)
    let offset = try PerfReuseDenialCensus.byteCount(at: trace)
    let writer = try FileHandle(forWritingTo: trace)
    try writer.seekToEnd()
    try writer.write(contentsOf: Data("[REUSE-TRACE] recompute-reasons: fresh=2\n".utf8))
    try writer.close()
    try PerfReuseDenialCensus.writeIfPresent(traceURL: trace, to: output, startingAt: offset)
    let census = try JSONDecoder().decode(
      PerfReuseDenialCensus.self, from: Data(contentsOf: output))
    #expect(census.frameCount == 1)
    #expect(census.totalDenials == 2)
    #expect(census.reasonTotals == ["fresh": 2])
  }
}
