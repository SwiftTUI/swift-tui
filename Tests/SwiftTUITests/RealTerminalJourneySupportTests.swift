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
      guard case .timedOut = error else {
        Issue.record("expected timedOut, got \(error)")
        return
      }
    }
  }

  @Test("visible-screen wait remains bounded under continuous output")
  func visibleScreenWaitRemainsBoundedUnderContinuousOutput() async throws {
    let pty = try RealTerminalPTYPair.open(size: CellSize(width: 80, height: 24))
    var screen = ANSIVisibleScreen(size: CellSize(width: 80, height: 24))
    let slave = pty.slave
    let writer = Task.detached {
      let chunk = Array(repeating: UInt8(ascii: "x"), count: 4_096)
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
        deadline: .now() + .milliseconds(100)
      ) { _ in false }
      Issue.record("expected continuous output to time out")
    } catch let error as RealTerminalJourneyError {
      guard case .timedOut = error else {
        Issue.record("expected timedOut, got \(error)")
        writer.cancel()
        pty.close()
        _ = await writer.value
        return
      }
    }

    writer.cancel()
    pty.close()
    _ = await writer.value
    #expect(startedAt.duration(to: clock.now) < .seconds(2))
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
