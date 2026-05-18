import Foundation
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct InputBatchingResponsivenessTests {
  @Test("pointer batching keeps a short debounce window")
  func pointerBatchingUsesShortDebounce() {
    #expect(InputReaderTiming.mouseEventFlushDelayMilliseconds == 1)
    #expect(
      RunLoop<EventBatchProbeState, EmptyView>.EventPumpTiming.coalescedPointerDrainYieldCount == 4
    )
  }

  /// Regression for the gallery's "scroll does nothing until I
  /// click" bug.  Root cause: the dispatch-source-based input
  /// reader's pending-mouse flush was rescheduled on EVERY
  /// incoming event, so a continuous high-rate burst (trackpad
  /// momentum scroll, gaming mouse) kept pushing the flush
  /// deadline forward indefinitely.  The flush only fired when
  /// the input stream went idle — meaning scroll events sat in
  /// the pending buffer until an unrelated click forced a flush.
  ///
  /// The fix: only the FIRST event in a cluster arms the flush
  /// timer.  Subsequent events while a flush is already pending
  /// append to the cluster but do NOT re-arm.  This is captured
  /// by ``MouseEventCoalescingState.append`` returning a
  /// "should arm flush timer" boolean.
  ///
  /// This test pins that schedule-once-per-cluster invariant
  /// directly against the state machine, so the regression can be
  /// caught deterministically without depending on dispatch-source
  /// timing or wall-clock scheduling.
  @Test("MouseEventCoalescingState arms flush only on the first event in a cluster")
  func mouseEventCoalescingStateArmsFlushOncePerCluster() {
    let state = MouseEventCoalescingState()

    let firstScroll: InputEvent = .mouse(
      .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 5, y: 5))
    )
    let secondScroll: InputEvent = .mouse(
      .init(kind: .scrolled(deltaX: 0, deltaY: 2), location: .init(x: 5, y: 5))
    )
    let thirdScroll: InputEvent = .mouse(
      .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 5, y: 5))
    )

    // First event in a cluster arms the flush timer.
    #expect(state.append(firstScroll) == true)
    #expect(state.isFlushScheduled)
    #expect(state.pendingEvents.count == 1)

    // Subsequent events do NOT re-arm — this is the invariant
    // the gallery bug regressed against.
    #expect(state.append(secondScroll) == false)
    #expect(state.append(thirdScroll) == false)
    #expect(state.isFlushScheduled, "isFlushScheduled stays armed across the cluster")
    #expect(state.pendingEvents.count == 3)

    // Drain returns all events and clears the armed flag, so
    // the next appended event starts a new cluster.
    let drained = state.drain()
    #expect(drained.count == 3)
    #expect(!state.isFlushScheduled)
    #expect(state.pendingEvents.isEmpty)

    let nextScroll: InputEvent = .mouse(
      .init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 5, y: 5))
    )
    #expect(
      state.append(nextScroll) == true,
      "after drain, the next event must arm a fresh cluster"
    )
  }

  @Test("readTerminalInputChunk returns bytes then wouldBlock for a nonblocking pipe")
  func terminalInputChunkReadClassifiesBytesAndWouldBlock() throws {
    let pipe = try makeNonblockingPipe()
    defer {
      close(pipe.readEnd)
      close(pipe.writeEnd)
    }

    try writeAll(Array("abc".utf8), to: pipe.writeEnd)

    #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: 8) == .bytes(Array("abc".utf8)))
    #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: 8) == .wouldBlock)
  }

  @Test("readTerminalInputChunk returns endOfFile after the writer closes")
  func terminalInputChunkReadClassifiesEndOfFile() throws {
    let pipe = try makeNonblockingPipe()
    defer {
      close(pipe.readEnd)
    }

    close(pipe.writeEnd)

    #expect(readTerminalInputChunk(from: pipe.readEnd, maxBytes: 8) == .endOfFile)
  }

  @Test("drainAvailableTerminalInput accumulates chunks until wouldBlock")
  func terminalInputDrainAccumulatesUntilWouldBlock() throws {
    let pipe = try makeNonblockingPipe()
    defer {
      close(pipe.readEnd)
      close(pipe.writeEnd)
    }

    try writeAll(Array("abcdef".utf8), to: pipe.writeEnd)

    #expect(
      drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: 2)
        == TerminalInputDrainResult(bytes: Array("abcdef".utf8), shouldFinish: false)
    )
  }

  @Test("drainAvailableTerminalInput preserves drained bytes when EOF follows")
  func terminalInputDrainPreservesBytesBeforeEndOfFile() throws {
    let pipe = try makeNonblockingPipe()
    defer {
      close(pipe.readEnd)
    }

    try writeAll(Array("abcdef".utf8), to: pipe.writeEnd)
    close(pipe.writeEnd)

    #expect(
      drainAvailableTerminalInput(from: pipe.readEnd, maxBytesPerRead: 2)
        == TerminalInputDrainResult(bytes: Array("abcdef".utf8), shouldFinish: true)
    )
  }

  /// Sanity test for the dispatch-source-based InputReader: feed
  /// scroll bytes through a real pipe and confirm the consumer
  /// receives at least one scroll event.  This is a smoke test for
  /// the production code path that complements the deterministic
  /// state-machine test above; it does NOT attempt to reproduce
  /// the original bug (which depends on wall-clock timing across
  /// multiple dispatch source notifications and is flaky to
  /// reproduce under heavy parallel test load).
  @Test("dispatch-source InputReader yields scroll events fed through a pipe")
  func dispatchSourceReaderYieldsScrollEventsFromPipe() async throws {
    var pipeFDs: [Int32] = [0, 0]
    let pipeResult = unsafe pipeFDs.withUnsafeMutableBufferPointer { buffer in
      unsafe pipe(buffer.baseAddress!)
    }
    try #require(pipeResult == 0)
    let readEnd = pipeFDs[0]
    let writeEnd = pipeFDs[1]
    var didCloseReadEnd = false
    var didCloseWriteEnd = false
    defer {
      if !didCloseReadEnd {
        close(readEnd)
      }
      if !didCloseWriteEnd {
        close(writeEnd)
      }
    }

    let flags = fcntl(readEnd, F_GETFL)
    _ = fcntl(readEnd, F_SETFL, flags | O_NONBLOCK)

    let reader = InputReader(fileDescriptor: readEnd)
    let receivedEvents = LockedBox<[InputEvent]>([])
    // Construct the stream before writing so the dispatch source is installed
    // even when the consumer task is delayed by the full parallel test suite.
    let inputEvents = reader.inputEvents()

    let consumerTask = Task {
      for await event in inputEvents {
        receivedEvents.withLock { events in
          events.append(event)
          return ()
        }
      }
    }
    defer {
      consumerTask.cancel()
    }

    let scrollEventBytes: [UInt8] = Array("\u{1B}[<64;5;5M".utf8)
    let bytesWritten = unsafe scrollEventBytes.withUnsafeBufferPointer { buffer in
      unsafe write(writeEnd, buffer.baseAddress, buffer.count)
    }
    #expect(bytesWritten == scrollEventBytes.count)

    func receivedScrollEvent() -> Bool {
      receivedEvents.value.contains { event in
        if case .mouse(let mouse) = event,
          case .scrolled = mouse.kind
        {
          return true
        }
        return false
      }
    }

    // Wait for the consumer task to drain the pipe and yield the event.  Keep
    // the write end open until the event arrives so the dispatch source cannot
    // observe EOF before its pending mouse flush runs under heavy test load.
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      if receivedScrollEvent() {
        break
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(
      receivedScrollEvent(),
      "the consumer must see at least one scroll event from the pipe"
    )

    close(writeEnd)
    didCloseWriteEnd = true
    _ = close(readEnd)
    didCloseReadEnd = true
  }

  @Test("pointer burst coalescing still preserves event boundaries")
  func coalescedPointerBurstsStillMerge() {
    let events: [InputEvent] = [
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 1), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 2), location: .init(x: 2, y: 3))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 4, y: 1))),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
      .key(.character("q")),
      .mouse(.init(kind: .moved, location: .init(x: 1, y: 1))),
      .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
      .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
    ]

    #expect(
      coalescedInputEvents(events) == [
        .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 2, y: 3))),
        .mouse(.init(kind: .dragged(.primary), location: .init(x: 7, y: 1))),
        .key(.character("q")),
        .mouse(.init(kind: .moved, location: .init(x: 3, y: 1))),
        .mouse(.init(kind: .down(.primary), location: .init(x: 3, y: 1))),
      ])
  }

  @Test("pointer burst coalescing flushes precision changes")
  func coalescedPointerBurstsFlushPrecisionChanges() {
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    let cellScroll = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 1),
      location: .cellFallback(CellPoint(x: 2, y: 3))
    )
    let subCellScroll = MouseEvent(
      kind: .scrolled(deltaX: 0, deltaY: 2),
      location: .subCell(
        location: Point(x: 2.25, y: 3.75),
        source: .terminalPixels,
        metrics: metrics,
        rawPixel: PixelPoint(x: 18, y: 60)
      )
    )

    #expect(
      coalescedInputEvents([.mouse(cellScroll), .mouse(subCellScroll)]) == [
        .mouse(cellScroll),
        .mouse(subCellScroll),
      ])
  }
}

private struct EventBatchProbeState: Equatable, Sendable {}

private func makeNonblockingPipe() throws -> (readEnd: Int32, writeEnd: Int32) {
  var pipeFDs: [Int32] = [0, 0]
  let pipeResult = unsafe pipeFDs.withUnsafeMutableBufferPointer { buffer in
    unsafe pipe(buffer.baseAddress!)
  }
  try #require(pipeResult == 0)

  let readEnd = pipeFDs[0]
  let flags = fcntl(readEnd, F_GETFL)
  try #require(flags >= 0)
  try #require(fcntl(readEnd, F_SETFL, flags | O_NONBLOCK) >= 0)

  return (readEnd: readEnd, writeEnd: pipeFDs[1])
}

private func writeAll(
  _ bytes: [UInt8],
  to fileDescriptor: Int32
) throws {
  try bytes.withUnsafeBufferPointer { buffer in
    var written = 0
    while written < bytes.count {
      let result = unsafe write(
        fileDescriptor,
        buffer.baseAddress!.advanced(by: written),
        bytes.count - written
      )
      try #require(result > 0)
      written += result
    }
  }
}
