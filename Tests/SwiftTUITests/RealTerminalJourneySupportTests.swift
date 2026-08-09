import Dispatch
import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@Suite
struct RealTerminalJourneySupportTests {
  @Test("ANSI visible screen handles fragmented terminal output")
  func ansiVisibleScreenHandlesFragmentedOutput() {
    var screen = ANSIVisibleScreen(size: CellSize(width: 12, height: 3))

    screen.feed(Array("stale".utf8))
    screen.feed([0x1B, 0x5B, 0x32])
    screen.feed(Array("J\u{001B}[2;3HHi".utf8))

    let emojiBytes = Array("🙂".utf8)
    screen.feed(Array(emojiBytes.prefix(2)))
    screen.feed(Array(emojiBytes.dropFirst(2)))

    screen.feed(Array("\u{001B}]0;ignored\u{0007}\u{001B}[K".utf8))

    #expect(screen.renderedText == "\n  Hi🙂\n")
  }

  @Test("ANSI visible screen models DECSTBM scroll regions with SU and SD")
  func ansiVisibleScreenModelsScrollRegions() {
    // Rows: A/B/C/D on a 4-row screen. Region rows 2..3 (1-based CSI 2;3r).
    var screen = ANSIVisibleScreen(size: CellSize(width: 4, height: 4))
    screen.feed(Array("\u{001B}[1;1HA\u{001B}[2;1HB\u{001B}[3;1HC\u{001B}[4;1HD".utf8))
    #expect(screen.renderedText == "A\nB\nC\nD")

    // SU inside the region: B/C slide up to B←C with a blank at the region
    // bottom; A and D (outside the region) must not move.
    screen.feed(Array("\u{001B}[2;3r\u{001B}[1S".utf8))
    #expect(screen.renderedText == "A\nC\n\nD")

    // SD scrolls the region back down: blank at the region top.
    screen.feed(Array("\u{001B}[1T".utf8))
    #expect(screen.renderedText == "A\n\nC\nD")

    // DECSTBM homes the cursor: the next glyph lands at the origin.
    screen.feed(Array("\u{001B}[r".utf8))
    screen.feed(Array("X".utf8))
    #expect(screen.renderedText == "X\n\nC\nD")

    // With the region reset, SU moves the full screen.
    screen.feed(Array("\u{001B}[1S".utf8))
    #expect(screen.renderedText == "\nC\nD\n")
  }

  @Test("visible-screen wait rejects an already-expired deadline")
  func visibleScreenWaitRejectsExpiredDeadline() async throws {
    let pty = try RealTerminalPTYPair.open(size: CellSize(width: 12, height: 3))
    defer { pty.close() }
    var screen = ANSIVisibleScreen(size: CellSize(width: 12, height: 3))

    do {
      _ = try await waitForANSIVisibleScreen(
        on: pty.master,
        screen: &screen,
        deadline: .now()
      ) { _ in true }
      Issue.record("expected an expired deadline to time out")
    } catch let error as RealTerminalJourneyError {
      guard case .timedOut(_, let transcript) = error else {
        Issue.record("expected timedOut, got \(error)")
        return
      }
      // A silent host must be distinguishable from one that wrote only
      // invisible control sequences; both render a blank screen.
      #expect(transcript.byteCount == 0)
      #expect(transcript.tail.isEmpty)
      #expect(error.description.contains("wrote 0 bytes"))
    }
  }

  @Test("visible-screen wait remains bounded under continuous output")
  func visibleScreenWaitRemainsBoundedUnderContinuousOutput() async throws {
    let pty = try RealTerminalPTYPair.open(size: CellSize(width: 80, height: 24))
    var screen = ANSIVisibleScreen(size: CellSize(width: 80, height: 24))
    let slave = pty.slave
    // Seed a small burst synchronously before arming the wait: on a starved
    // CI runner the detached writer may not be scheduled inside the wait
    // window at all, and this test measures transcript reporting under
    // output, not task-startup latency. The seed must stay well under the
    // smallest PTY input queue (macOS caps near 1 KiB) — with no reader
    // armed yet, a larger synchronous write deadlocks the test.
    let seed = Array(repeating: UInt8(ascii: "x"), count: 256)
    try writeAllBytes(seed, to: slave)
    let chunk = Array(repeating: UInt8(ascii: "x"), count: 4_096)
    let writer = Task.detached {
      while !Task.isCancelled {
        do {
          try writeAllBytes(chunk, to: slave)
        } catch {
          return
        }
      }
    }
    let clock = ContinuousClock()
    let startedAt = clock.now

    do {
      _ = try await waitForANSIVisibleScreen(
        on: pty.master,
        screen: &screen,
        deadline: .now() + .seconds(1)
      ) { _ in false }
      Issue.record("expected continuous output to time out")
    } catch let error as RealTerminalJourneyError {
      guard case .timedOut(_, let transcript) = error else {
        Issue.record("expected timedOut, got \(error)")
        writer.cancel()
        pty.close()
        _ = await writer.value
        return
      }
      // The counterpart to the silent case: a host that did write is reported
      // as such, and the retained tail stays bounded under a flood.
      #expect(transcript.byteCount > 0)
      #expect(!transcript.tail.isEmpty)
      #expect(transcript.tail.count <= 512)
      #expect(!error.description.contains("wrote 0 bytes"))
    }

    writer.cancel()
    pty.close()
    _ = await writer.value
    #expect(startedAt.duration(to: clock.now) < .seconds(5))
  }

  @Test("cancelling a visible-screen wait tears down its readable source")
  func cancellingVisibleScreenWaitTearsDownReadableSource() async throws {
    let pty = try RealTerminalPTYPair.open(size: CellSize(width: 12, height: 3))
    defer { pty.close() }
    let reachedCondition = Mutex(false)
    let conditionSignal = ConditionSignal()
    let waitTask = Task {
      var screen = ANSIVisibleScreen(size: CellSize(width: 12, height: 3))
      return try await waitForANSIVisibleScreen(
        on: pty.master,
        screen: &screen,
        deadline: .now() + .seconds(10)
      ) { _ in
        reachedCondition.withLock { $0 = true }
        conditionSignal.notify()
        return false
      }
    }

    await conditionSignal.wait {
      reachedCondition.withLock { $0 }
    }
    waitTask.cancel()

    do {
      _ = try await waitTask.value
      Issue.record("expected the visible-screen wait to propagate cancellation")
    } catch is CancellationError {
      pty.closeMaster()
    } catch {
      Issue.record("expected CancellationError, got \(error)")
    }
  }
}
