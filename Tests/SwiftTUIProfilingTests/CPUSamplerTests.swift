import Testing

@testable import SwiftTUIProfiling

@Suite
struct CPUSamplerTests {
  @Test("readCurrentUsage returns a non-negative reading")
  func readsUsage() throws {
    let reading = try CPUSampler.readCurrentUsage()
    #expect(reading.userCPUSeconds >= 0)
    #expect(reading.systemCPUSeconds >= 0)
    #expect(reading.maxResidentBytes >= 0)
    #expect(reading.totalCPUSeconds == reading.userCPUSeconds + reading.systemCPUSeconds)
  }

  @Test("sampleDelta over real CPU work is non-negative and carries RSS")
  func computesDelta() throws {
    let start = try CPUSampler.readCurrentUsage()
    // Burn CPU (no sleep) so the delta and wall time are observable.
    var sink = 0
    for value in 0..<5_000_000 {
      sink = sink &+ value
    }
    #expect(sink != 0)
    let end = try CPUSampler.readCurrentUsage()

    let sample = CPUSampler.sampleDelta(from: start, to: end)
    #expect(sample.userCPUSeconds >= 0)
    #expect(sample.systemCPUSeconds >= 0)
    #expect(sample.totalCPUSeconds == sample.userCPUSeconds + sample.systemCPUSeconds)
    #expect(sample.wallDeltaSeconds >= 0)
    #expect(sample.estimatedCPUPercent >= 0)
    #expect(sample.maxResidentBytes == end.maxResidentBytes)
  }

  @Test("deltas produces one sample per consecutive reading pair")
  func deltasCount() throws {
    let readings = try (0..<3).map { _ in try CPUSampler.readCurrentUsage() }
    #expect(CPUSampler.deltas(from: readings).count == 2)
  }
}
