import Testing

@testable import SwiftTUICore
@testable import SwiftTUIProfiling
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct ProfileSinkTests {
  private func cpuSample(percent: Double, residentBytes: Int) -> CPUSample {
    CPUSample(
      timestampSeconds: 1,
      userCPUSeconds: 0.5,
      systemCPUSeconds: 0.1,
      totalCPUSeconds: 0.6,
      wallDeltaSeconds: 1,
      estimatedCPUPercent: percent,
      maxResidentBytes: residentBytes
    )
  }

  @Test("HandlerSink forwards every emitted record")
  func handlerForwards() {
    let box = RecordBox()
    let sink = HandlerSink { box.records.append($0) }
    sink.emit(.memory([MemoryMetricSnapshot(name: "A", count: 3)]))
    sink.emit(.cpu(cpuSample(percent: 10, residentBytes: 0)))
    #expect(box.records.count == 2)
  }

  @Test("SummarySink reduces memory and CPU observations")
  func summaryReduces() {
    let sink = SummarySink()
    sink.emit(.memory([MemoryMetricSnapshot(name: "TextLayoutCache.entries", count: 10)]))
    sink.emit(.memory([MemoryMetricSnapshot(name: "TextLayoutCache.entries", count: 25)]))
    sink.emit(.cpu(cpuSample(percent: 60, residentBytes: 2_097_152)))

    let report = sink.report()
    #expect(report.contains("TextLayoutCache.entries: 25 / 25"))
    #expect(report.contains("cpu: peak 60%"))
    #expect(report.contains("rss peak 2MB"))
  }

  @Test("SummarySink reports max above last when occupancy receded")
  func summaryTracksMax() {
    let sink = SummarySink()
    sink.emit(.memory([MemoryMetricSnapshot(name: "Cache", count: 50)]))
    sink.emit(.memory([MemoryMetricSnapshot(name: "Cache", count: 20)]))
    #expect(sink.report().contains("Cache: 20 / 50"))
  }
}

@MainActor
private final class RecordBox {
  var records: [ProfileRecord] = []
}
