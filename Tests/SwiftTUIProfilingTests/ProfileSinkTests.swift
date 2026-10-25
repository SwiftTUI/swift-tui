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

  // STUI-1228: the report converted an infinite CPU peak and an unbounded
  // frame duration with unchecked Int(_:).
  @Test("SummarySink ignores non-finite CPU samples and saturates huge values")
  func summaryNonFiniteAndHugeValues() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run {
        func sample(_ percent: Double) -> CPUSample {
          CPUSample(
            timestampSeconds: 1, userCPUSeconds: 0, systemCPUSeconds: 0, totalCPUSeconds: 0,
            wallDeltaSeconds: 1, estimatedCPUPercent: percent, maxResidentBytes: 0)
        }
        let mixed = SummarySink()
        mixed.emit(.cpu(sample(.infinity)))
        mixed.emit(.cpu(sample(150)))
        #expect(mixed.report().contains("cpu: peak 150%"), "\(mixed.report())")
        let infinite = SummarySink()
        infinite.emit(.cpu(sample(.infinity)))
        infinite.emit(.cpu(sample(-.infinity)))
        #expect(!infinite.report().contains("cpu:"), "\(infinite.report())")
        let huge = SummarySink()
        huge.emit(.cpu(sample(1e300)))
        #expect(huge.report().contains("cpu: peak "), "\(huge.report())")
        var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "long")
        record.totalFrameDuration = .seconds(Int64.max)
        let long = SummarySink()
        long.emit(.frame(record))
        #expect(long.report().contains("worst total "), "\(long.report())")
      }
    }
  }

  @Test("SummarySink finite values keep their exact spelling")
  func summaryFiniteSpellingsAreUnchanged() {
    let sink = SummarySink()
    sink.emit(.cpu(cpuSample(percent: 99.5, residentBytes: 0)))
    var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "finite")
    record.totalFrameDuration = .milliseconds(12) + .microseconds(600)
    sink.emit(.frame(record))
    let report = sink.report()
    #expect(report.contains("cpu: peak 100%"), "\(report)")
    #expect(report.contains("worst total 13ms"), "\(report)")
  }
}

@MainActor
private final class RecordBox {
  var records: [ProfileRecord] = []
}
