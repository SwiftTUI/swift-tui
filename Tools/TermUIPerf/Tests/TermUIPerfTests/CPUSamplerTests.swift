import Testing

@testable import TermUIPerf

struct CPUSamplerTests {
  @Test("CPU sample delta computes user system total wall and percent")
  func cpuSampleDeltaComputesUserSystemTotalWallAndPercent() {
    let sample = CPUSampler.sampleDelta(
      from: ProcessCPUReading(
        timestampSeconds: 10,
        userCPUSeconds: 1.0,
        systemCPUSeconds: 2.0
      ),
      to: ProcessCPUReading(
        timestampSeconds: 12,
        userCPUSeconds: 1.25,
        systemCPUSeconds: 2.50
      )
    )

    #expect(sample.timestampSeconds == 12)
    #expect(sample.userCPUSeconds == 0.25)
    #expect(sample.systemCPUSeconds == 0.50)
    #expect(sample.totalCPUSeconds == 0.75)
    #expect(sample.wallDeltaSeconds == 2)
    #expect(sample.estimatedCPUPercent == 37.5)
  }

  @Test("CPU sample delta clamps backwards counters")
  func cpuSampleDeltaClampsBackwardsCounters() {
    let sample = CPUSampler.sampleDelta(
      from: ProcessCPUReading(
        timestampSeconds: 10,
        userCPUSeconds: 3.0,
        systemCPUSeconds: 2.0
      ),
      to: ProcessCPUReading(
        timestampSeconds: 9,
        userCPUSeconds: 2.0,
        systemCPUSeconds: 1.0
      )
    )

    #expect(sample.userCPUSeconds == 0)
    #expect(sample.systemCPUSeconds == 0)
    #expect(sample.totalCPUSeconds == 0)
    #expect(sample.wallDeltaSeconds == 0)
    #expect(sample.estimatedCPUPercent == 0)
  }

  @Test("platform sampler reads process CPU counters")
  func platformSamplerReadsProcessCPUCounters() throws {
    let reading = try CPUSampler.readCurrentUsage()

    #expect(reading.timestampSeconds > 0)
    #expect(reading.userCPUSeconds >= 0)
    #expect(reading.systemCPUSeconds >= 0)
    #expect(reading.totalCPUSeconds >= reading.userCPUSeconds)
  }

  @Test("periodic collector samples around async operation")
  func periodicCollectorSamplesAroundAsyncOperation() async throws {
    let samples = try await CPUSampler.collect(interval: .milliseconds(1)) {
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(samples.isEmpty == false)
    #expect(samples.allSatisfy { $0.wallDeltaSeconds >= 0 })
    #expect(samples.allSatisfy { $0.totalCPUSeconds >= 0 })
  }
}
