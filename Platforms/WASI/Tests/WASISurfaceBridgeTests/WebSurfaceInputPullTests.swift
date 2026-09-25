// Excluded from Windows builds: exercises the reader through pipe file
// descriptors and fcntl nonblocking flags.
#if !os(Windows)

  import SwiftTUICore
  @_spi(Runners) import SwiftTUIRuntime
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @testable import SwiftTUIWASISurfaceBridge

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Musl)
    import Musl
  #endif

  /// The WASI reader's pull delivery (plan 2026-09-24-001 §4D, STUI-618):
  /// one synchronous pull drains everything the ring holds, in order, without
  /// the stream adapter's 512-byte read cap or its task hops.
  @MainActor
  @Suite(.serialized)
  struct WebSurfaceInputPullTests {
    @Test("one pull delivers every queued record in order, past the old 512-byte cap")
    func onePullDrainsTheWholeSource() throws {
      let pipe = try NonblockingPipe()
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd)
      let recorder = PullRecorder()
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }

      // 2,000 key presses alternate so order is observable, well past the
      // stream adapter's 512-byte read.
      let bytes = (0..<2_000).map { UInt8($0.isMultiple(of: 2) ? 0x78 : 0x79) }
      try pipe.write(bytes)

      let delivered = reader.pullPendingInput()
      #expect(delivered == 2_000)
      #expect(recorder.keys.count == 2_000)
      #expect(recorder.keys == bytes.map { String(UnicodeScalar($0)) })
      #expect(recorder.sourceBytes == 2_000)
      #expect(recorder.sourceReads >= 1)
      #expect(recorder.inputEndedReports == 0)
      // Nothing more is pending: the next pull is empty and cheap.
      #expect(reader.pullPendingInput() == 0)
    }

    @Test("control records are handled at their position between input events")
    func controlRecordsKeepTheirPositionInTheSequence() throws {
      let pipe = try NonblockingPipe()
      let sequence = SequenceLedger()
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd) { message in
        if case .resize = message {
          sequence.append("resize")
        }
      }
      let recorder = PullRecorder(onKey: { sequence.append($0) })
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }

      try pipe.write(Array("a\u{1E}resize:80:24\nb".utf8))
      #expect(reader.pullPendingInput() == 2)
      #expect(sequence.entries == ["a", "resize", "b"])
    }

    @Test("end of input is reported exactly once, after the last delivered event")
    func endOfInputIsReportedOnce() throws {
      let pipe = try NonblockingPipe()
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd)
      let recorder = PullRecorder()
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }

      try pipe.write(Array("q".utf8))
      pipe.closeWriteEnd()

      // The same pull that drains the last byte sees EOF and reports it,
      // after delivering the byte.
      #expect(reader.pullPendingInput() == 1)
      #expect(recorder.keys == ["q"])
      #expect(recorder.inputEndedReports == 1)
      #expect(recorder.endedAfterKeyCount == 1)
      #expect(reader.pullPendingInput() == 0)
      #expect(reader.pullPendingInput() == 0)
      #expect(recorder.inputEndedReports == 1)
    }

    @Test("the idle poll delivers input to a loop that never pulls")
    func idlePollDeliversWithoutABoundaryPull() async throws {
      let pipe = try NonblockingPipe()
      let reader = WebSurfaceInputReader(fileDescriptor: pipe.readEnd)
      let recorder = PullRecorder()
      reader.installPullDelivery(recorder.sink)
      defer { reader.uninstallPullDelivery() }

      try pipe.write(Array("zz".utf8))
      // Signal-driven: the recorder notifies on each delivery; the deadline
      // event is only the failure bound.
      let deadline = AsyncEvent.firing(after: AsyncTestTimeouts.scaled(.seconds(5)))
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await recorder.delivered.wait(until: { recorder.keys.count >= 2 }) }
        group.addTask { await deadline.wait() }
        await group.next()
        group.cancelAll()
      }
      #expect(recorder.keys == ["z", "z"])
    }
  }

  // MARK: - Fixtures

  @MainActor
  private final class PullRecorder {
    let delivered = MainActorConditionSignal()
    private(set) var keys: [String] = []
    private(set) var sourceBytes = 0
    private(set) var sourceReads = 0
    private(set) var inputEndedReports = 0
    private(set) var endedAfterKeyCount: Int?
    private let onKey: (@MainActor (String) -> Void)?

    init(onKey: (@MainActor (String) -> Void)? = nil) {
      self.onKey = onKey
    }

    var sink: InputPullDeliverySink {
      InputPullDeliverySink(
        deliver: { [self] event in
          guard case .key(let press) = event, case .character(let character) = press.key else {
            return
          }
          let text = String(character)
          keys.append(text)
          onKey?(text)
          delivered.notify()
        },
        inputEnded: { [self] in
          inputEndedReports += 1
          endedAfterKeyCount = keys.count
        },
        recordSourceRead: { [self] bytes, _ in
          sourceBytes += bytes
          sourceReads += 1
        }
      )
    }
  }

  @MainActor
  private final class SequenceLedger {
    private(set) var entries: [String] = []

    nonisolated init() {}

    nonisolated func append(_ entry: String) {
      MainActor.assumeIsolated {
        entries.append(entry)
      }
    }
  }

  private struct NonblockingPipe {
    let readEnd: Int32
    private let writeEnd: Int32
    private let closedWriteEnd: Box

    private final class Box {
      var closed = false
    }

    init() throws {
      var descriptors: [Int32] = [-1, -1]
      try #require(unsafe pipe(&descriptors) == 0)
      readEnd = descriptors[0]
      writeEnd = descriptors[1]
      let flags = fcntl(readEnd, F_GETFL)
      try #require(fcntl(readEnd, F_SETFL, flags | O_NONBLOCK) == 0)
      closedWriteEnd = Box()
    }

    func write(_ bytes: [UInt8]) throws {
      var offset = 0
      while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBufferPointer { buffer in
          unsafe Darwin.write(writeEnd, buffer.baseAddress, buffer.count)
        }
        try #require(written > 0)
        offset += written
      }
    }

    func closeWriteEnd() {
      guard !closedWriteEnd.closed else { return }
      closedWriteEnd.closed = true
      _ = close(writeEnd)
    }
  }

#endif
