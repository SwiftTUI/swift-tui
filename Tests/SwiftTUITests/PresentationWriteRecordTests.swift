import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

#if canImport(Dispatch)
  import Dispatch
#endif

/// WP-1: the presentation writer reports every submission's fate.
///
/// The frame row in `frames.tsv` is emitted at commit; the `write(2)` that puts
/// its bytes on the wire completes later, on the writer queue. These cases pin
/// the contract the `presents.tsv` join depends on — **every** submission that
/// carries a frame ordinal produces exactly one record, whether it reached the
/// terminal or was superseded. Silence on the supersede path would fake the
/// dropped frame's write latency onto the frame that displaced it.
#if !canImport(WASILibc)
  struct PresentationWriteRecordTests {
    @Test("A written frame reports its bytes, its completion, and the written outcome")
    func writtenFrameReportsBytesAndCompletion() async throws {
      let controller = GatedWriteController()
      let sink = RecordingPresentationWriteSink()
      let writer = TerminalPresentationWriter(
        controller: controller,
        outputFileDescriptor: 1,
        writeSink: sink
      )

      let submittedAt = MonotonicInstant.now()
      writer.submit(
        .init(sequence: 1, output: "frame-one", frameOrdinal: 1, submittedAt: submittedAt)
      )
      await controller.gate.waitUntilBlocked()
      controller.gate.release()
      writer.drain()

      let records = sink.records
      #expect(records.count == 1)
      let record = try #require(records.first)
      #expect(record.frame == 1)
      #expect(record.outcome == .written)
      #expect(record.bytes == "frame-one".utf8.count)
      #expect(record.submittedAt == submittedAt)
      let writtenAt = try #require(record.writtenAt)
      #expect(writtenAt >= submittedAt)
    }

    @Test("A superseded submission is recorded as superseded, so the join stays total")
    func supersededSubmissionIsRecorded() async throws {
      let controller = GatedWriteController()
      let sink = RecordingPresentationWriteSink()
      let writer = TerminalPresentationWriter(
        controller: controller,
        outputFileDescriptor: 1,
        writeSink: sink
      )

      // Frame 1 is dequeued and stalls inside `write`.
      writer.submit(.init(sequence: 1, output: "one", frameOrdinal: 1, submittedAt: .now()))
      await controller.gate.waitUntilBlocked()

      // Frame 2 becomes pending; frame 3 replaces it before it is ever dequeued.
      writer.submit(.init(sequence: 2, output: "two", frameOrdinal: 2, submittedAt: .now()))
      writer.submit(.init(sequence: 3, output: "three", frameOrdinal: 3, submittedAt: .now()))

      controller.gate.release()
      writer.drain()

      let records = sink.records
      // The join is total over the drop sequence: three submissions, three rows.
      #expect(records.count == 3)
      #expect(Set(records.map(\.frame)) == [1, 2, 3])

      let superseded = try #require(records.first { $0.frame == 2 })
      #expect(superseded.outcome == .superseded)
      #expect(superseded.writtenAt == nil)
      #expect(superseded.bytes == "two".utf8.count)

      for frame in [1, 3] {
        let written = try #require(records.first { $0.frame == frame })
        #expect(written.outcome == .written)
        #expect(written.writtenAt != nil)
      }
      #expect(controller.writes == ["one", "three"])
    }

    @Test("Discarding a pending frame before planning records it as superseded")
    func reconcileBeforePlanningRecordsSupersession() async throws {
      let controller = GatedWriteController()
      let sink = RecordingPresentationWriteSink()
      let writer = TerminalPresentationWriter(
        controller: controller,
        outputFileDescriptor: 1,
        writeSink: sink
      )

      writer.submit(.init(sequence: 1, output: "one", frameOrdinal: 1, submittedAt: .now()))
      await controller.gate.waitUntilBlocked()
      writer.submit(.init(sequence: 2, output: "two", frameOrdinal: 2, submittedAt: .now()))

      // The host is about to plan a fresh frame and drops the pending one.
      _ = writer.reconcileBeforePlanning()

      controller.gate.release()
      writer.drain()

      let records = sink.records
      #expect(records.count == 2)
      #expect(records.first { $0.frame == 1 }?.outcome == .written)
      #expect(records.first { $0.frame == 2 }?.outcome == .superseded)
      #expect(controller.writes == ["one"])
    }

    @Test("Supplemental output carries no frame ordinal and produces no row")
    func supplementalOutputIsNotRecorded() throws {
      let controller = GatedWriteController(gatesFirstWrite: false)
      let sink = RecordingPresentationWriteSink()
      let writer = TerminalPresentationWriter(
        controller: controller,
        outputFileDescriptor: 1,
        writeSink: sink
      )

      // Accessibility cursor output: no cell content, no frame ordinal, and
      // nothing for a per-frame join to key on.
      writer.submitSupplementalOutput("\u{1B}[3;5H")
      writer.drain()

      #expect(sink.records.isEmpty)
      #expect(controller.writes == ["\u{1B}[3;5H"])
    }

    @Test("With no sink installed the writer records nothing and still writes")
    func unarmedWriterIsInert() throws {
      let controller = GatedWriteController(gatesFirstWrite: false)
      let writer = TerminalPresentationWriter(
        controller: controller,
        outputFileDescriptor: 1
      )

      writer.submit(.init(sequence: 1, output: "one", frameOrdinal: 1, submittedAt: .now()))
      writer.drain()

      #expect(controller.writes == ["one"])
    }
  }

  // MARK: - Doubles

  private final class RecordingPresentationWriteSink: PresentationWriteSink {
    private let storage = Mutex<[PresentationWriteSample]>([])

    var records: [PresentationWriteSample] {
      storage.withLock { $0 }
    }

    func record(_ sample: PresentationWriteSample) {
      storage.withLock { $0.append(sample) }
    }
  }

  /// A controller whose first `write` stalls its own thread until released, so
  /// a test can deterministically park one frame in flight and supersede the
  /// next. A semaphore is the correct primitive here: `write` is synchronous
  /// and must genuinely block the writer queue's thread.
  private final class GatedWriteController: TerminalControlling {
    let gate: BlockingWriteGate
    private let writesStorage = Mutex<[String]>([])

    var writes: [String] {
      writesStorage.withLock { $0 }
    }

    init(gatesFirstWrite: Bool = true) {
      gate = BlockingWriteGate(arms: gatesFirstWrite)
    }

    func isATTY(_: Int32) -> Bool { true }

    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      TerminalModeSnapshot()
    }

    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}

    func windowSize(of _: Int32) throws -> CellSize { .init(width: 80, height: 24) }

    func cellPixelSize(of _: Int32) throws -> PixelSize? { nil }



    func write(_ output: String, to _: Int32) throws {
      gate.enterBlockingSection()
      writesStorage.withLock { $0.append(output) }
    }

    func read(
      from _: Int32,
      maxBytes _: Int,
      timeoutMilliseconds _: Int
    ) throws -> [UInt8] {
      []
    }
  }
#endif
