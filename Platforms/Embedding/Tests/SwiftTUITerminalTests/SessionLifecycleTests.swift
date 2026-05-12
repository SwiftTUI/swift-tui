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
    try await session.start()

    try await waitUntil("session exit") {
      if case .exited = await session.currentLifecycle() {
        return true
      }
      return false
    }

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
    try await session.start()

    try await waitUntil("child output") {
      let snap = await session.snapshot()
      guard let firstRow = snap.cells.first else {
        return false
      }
      let firstTwo = firstRow.prefix(2).map(\.character)
      return firstTwo == ["h", "i"]
    }

    try await waitUntil("session exit") {
      if case .exited = await session.currentLifecycle() {
        return true
      }
      return false
    }
  }
}

private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 50_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let start = ContinuousClock.now
  while !(await condition()) {
    if start.duration(to: ContinuousClock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw SessionLifecycleTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct SessionLifecycleTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
