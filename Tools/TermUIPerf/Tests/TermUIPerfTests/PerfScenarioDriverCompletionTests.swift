@_spi(Runners) import SwiftTUI
import Synchronization
import Testing

@testable import TermUIPerf

@MainActor
struct PerfScenarioDriverCompletionTests {
  @Test("quiescence waits a full idle interval after the latest frame", arguments: [0, 1, 2])
  func quiescenceResetsOnNewFrames(frameAtSleep: Int) async throws {
    let driver = makeDriver()
    var now = ContinuousClock().now
    var sleeps = 0
    try await driver.waitForQuiescence(
      idle: .milliseconds(2), timeout: .milliseconds(10), now: { now },
      sleep: {
        sleeps += 1
        now = now.advanced(by: .milliseconds(1))
        if sleeps == frameAtSleep {
          try presentFrame(in: driver.terminalHost)
        }
      }
    )
    #expect(sleeps == (frameAtSleep == 0 ? 2 : frameAtSleep + 2))
  }

  @Test("continuous presentations reach an explicit quiescence timeout")
  func continuousFramesTimeOut() async throws {
    let driver = makeDriver()
    var now = ContinuousClock().now
    var sleeps = 0
    do {
      try await driver.waitForQuiescence(
        idle: .milliseconds(2), timeout: .milliseconds(3), now: { now },
        sleep: {
          sleeps += 1
          now = now.advanced(by: .milliseconds(1))
          try presentFrame(in: driver.terminalHost)
        }
      )
      Issue.record("continuous frames must not count as quiescence")
    } catch {
      #expect(error as? PerfScenarioError == .quiescenceTimedOut)
    }
    #expect(sleeps == 3)
  }

  @Test("quiescence rejects cancellation before an already-satisfied idle interval")
  func quiescenceChecksCancellationBeforeSuccess() async throws {
    let driver = makeDriver()
    let task = Task { @MainActor in
      try await driver.waitForQuiescence(
        idle: .zero, timeout: .seconds(1), now: { ContinuousClock().now },
        sleep: { Issue.record("cancelled wait must not sleep") }
      )
    }
    task.cancel()
    await expectCancellation(of: task)
  }

  @Test("cancelled quiescence stops even when its sleeper returns normally")
  func quiescenceChecksCancellationAfterSleep() async throws {
    let driver = makeDriver()
    let sleeper = ControlledPerfSleeper()
    var entered = sleeper.entered.stream.makeAsyncIterator()
    var now = ContinuousClock().now
    let task = Task { @MainActor in
      try await driver.waitForQuiescence(
        idle: .seconds(1), timeout: .seconds(2), now: { now },
        sleep: {
          try await sleeper.sleep(for: .milliseconds(1))
          // If cancellation is ignored, fail with the wrong timeout result
          // rather than suspending this regression a second time forever.
          now = now.advanced(by: .seconds(3))
        }
      )
    }
    _ = await entered.next()
    task.cancel()
    await sleeper.release(throwsCancellation: false)
    await expectCancellation(of: task)
  }

  @Test("cancelled pacing cannot emit the remaining scroll burst", arguments: [false, true])
  func scrollStopsAfterCancellation(throwsCancellation: Bool) async throws {
    let driver = makeDriver()
    let stream = driver.inputReader.inputEvents()
    let sleeper = ControlledPerfSleeper()
    var entered = sleeper.entered.stream.makeAsyncIterator()
    let task = Task { @MainActor in
      try await driver.driveScroll(
        cadence: .milliseconds(1), notches: 180, at: CellPoint(x: 2, y: 3),
        sleep: { try await sleeper.sleep(for: $0) }
      )
    }
    _ = await entered.next()
    task.cancel()
    await sleeper.release(throwsCancellation: throwsCancellation)
    await expectCancellation(of: task)
    driver.inputReader.finish()
    var count = 0
    for await _ in stream { count += 1 }
    #expect(count == 1)
    #expect(driver.terminalHost.presentedFrames.isEmpty)
  }

  @Test("cancellation before pacing starts emits no scroll event")
  func scrollCancelledBeforeStart() async throws {
    let driver = makeDriver()
    let stream = driver.inputReader.inputEvents()
    let task = Task { @MainActor in
      try await driver.driveScroll(
        cadence: .milliseconds(1), notches: 180, at: CellPoint(x: 2, y: 3),
        sleep: { _ in Issue.record("cancelled drive must not sleep") }
      )
    }
    task.cancel()
    await expectCancellation(of: task)
    driver.inputReader.finish()
    var count = 0
    for await _ in stream { count += 1 }
    #expect(count == 0)
  }

  private func makeDriver() -> PerfScenarioDriver {
    PerfScenarioDriver(
      inputReader: PerfScriptedInputReader(),
      terminalHost: PerfTerminalHost(size: PerfTerminalSize(columns: 8, rows: 1))
    )
  }

  private func presentFrame(in host: PerfTerminalHost) throws {
    _ = try host.present(RasterSurface(size: CellSize(width: 8, height: 1), lines: ["tick"]))
  }

  private func expectCancellation(of task: Task<Void, any Error>) async {
    do {
      try await task.value
      Issue.record("expected cancellation")
    } catch {
      #expect(error is CancellationError)
    }
  }
}

actor ControlledPerfSleeper {
  let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let cancelled = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  private var continuation: CheckedContinuation<Void, any Error>?
  private var didSuspend = false
  private nonisolated let cancellationObserved = Mutex(false)

  nonisolated var didObserveCancellation: Bool {
    cancellationObserved.withLock { $0 }
  }

  func sleep(for _: Duration) async throws {
    guard !didSuspend else { throw ControlledSleepError.unexpectedAdditionalSleep }
    didSuspend = true
    let cancellation = cancelled.continuation
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        #expect(self.continuation == nil)
        self.continuation = continuation
        entered.continuation.yield(())
      }
    } onCancel: {
      self.cancellationObserved.withLock { $0 = true }
      cancellation.yield(())
    }
  }

  func release(throwsCancellation: Bool) {
    let suspended = continuation
    continuation = nil
    #expect(suspended != nil)
    if throwsCancellation {
      suspended?.resume(throwing: CancellationError())
    } else {
      suspended?.resume()
    }
  }
}

private enum ControlledSleepError: Error {
  case unexpectedAdditionalSleep
}
