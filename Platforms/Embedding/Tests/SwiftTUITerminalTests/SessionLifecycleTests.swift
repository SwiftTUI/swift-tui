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
}
