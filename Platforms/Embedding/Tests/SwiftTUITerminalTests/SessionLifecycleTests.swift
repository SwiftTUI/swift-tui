import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminal

@Suite("TerminalProcessSession lifecycle", .serialized)
struct SessionLifecycleTests {
  @Test("session reaches .running after start, .exited after child exits")
  func runToExit() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "echo hi; exit 0"],
      initialSize: CellSize(width: 40, height: 10)
    )
    // Register the event stream before `start()`: the pump task finishes it
    // immediately after `markExited`, so draining it is a direct, poll-free
    // await for the child's exit — no wall-clock timeout.
    let sessionEvents = session.events()
    try await session.start()
    for await _ in sessionEvents {}

    if case .exited(let reason) = await session.currentLifecycle() {
      #expect(reason == .normal(code: 0))
    } else {
      Issue.record("session never exited")
    }
  }

  @Test("event streams subscribed after exit finish immediately")
  func eventsAfterExitFinishImmediately() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "exit 0"],
      initialSize: CellSize(width: 40, height: 10)
    )
    let sessionEvents = session.events()
    try await session.start()
    for await _ in sessionEvents {}

    // A subscription arriving after the pump finished the broadcaster must
    // terminate at once — a pane revisiting an exited session would
    // otherwise await a stream nobody will ever finish. On regression this
    // drain never returns and the suite's hang watchdog fails the run.
    for await _ in session.events() {}

    #expect(
      await session.currentLifecycle() == .exited(reason: .normal(code: 0))
    )
  }

  @Test("snapshot reflects child output")
  func snapshotShowsOutput() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "printf hi; sleep 0.5"],
      initialSize: CellSize(width: 10, height: 1)
    )
    let sessionEvents = session.events()
    try await session.start()
    for await _ in sessionEvents {}

    // After the session has exited the final emulator snapshot retains the
    // child's output, so asserting it here tests the same thing the
    // mid-run poll did, deterministically.
    let snap = await session.snapshot()
    let firstRow = try #require(snap.cells.first)
    let firstTwo = firstRow.prefix(2).map(\.character)
    #expect(firstTwo == ["h", "i"])
  }

  @Test("termination before start closes the session and prevents a later child launch")
  func terminateBeforeStartPreventsLaunch() async throws {
    let marker = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-tui-terminal-never-started-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: ["-c", "touch \"\(marker.path)\""],
      initialSize: CellSize(width: 40, height: 10)
    )
    let sessionEvents = session.events()

    await session.terminate()
    try await session.start()
    for await _ in sessionEvents {}

    #expect(
      await session.currentLifecycle()
        == .exited(reason: .sessionClosed)
    )
    #expect(!FileManager.default.fileExists(atPath: marker.path))
  }

  @Test("start racing termination cannot lose the termination request")
  func startRacingTerminationDoesNotLoseSignal() async throws {
    for _ in 0..<20 {
      let session = TerminalProcessSession(
        command: "/bin/sleep",
        arguments: ["10"],
        initialSize: CellSize(width: 40, height: 10)
      )

      async let start: Void = session.start()
      async let terminate: Void = session.terminate()
      _ = try await (start, terminate)

      let clock = ContinuousClock()
      let deadline = clock.now + .seconds(2)
      while clock.now < deadline {
        if case .exited = await session.currentLifecycle() {
          break
        }
        await Task.yield()
      }
      if case .exited = await session.currentLifecycle() {
        continue
      }

      await session.terminate(signal: 9)
      let cleanupDeadline = clock.now + .seconds(2)
      while clock.now < cleanupDeadline {
        if case .exited = await session.currentLifecycle() {
          break
        }
        await Task.yield()
      }
      if case .exited = await session.currentLifecycle() {
        Issue.record("session required fallback SIGKILL after a raced termination request")
      } else {
        Issue.record("session remained running after fallback SIGKILL")
      }
      return
    }
  }
}
