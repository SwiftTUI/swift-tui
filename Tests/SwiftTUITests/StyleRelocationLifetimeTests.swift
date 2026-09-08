@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StyleRelocationLifetimeTests {
  @Test(
    "captured tasks stop on omission, restart on return, and survive relocation",
    arguments: [false, true])
  func tasks(menu: Bool) async throws {
    let probe = StyleLifetimeProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StyleLifetime"), size: .init(width: 55, height: 15)
    ) { StyleLifetimeFixture(menu: menu, probe: probe) }
    defer { harness.shutdown() }
    if menu { _ = try harness.clickText("Commands") }
    try await waitForStyleLifetime { probe.starts == 1 }
    _ = try harness.clickText("Retained 0")
    #expect(harness.frame.contains("Retained 1"))
    let childIdentity = try harness.focusIdentity(forText: "Retained")
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    if menu {
      #expect(try harness.focusIdentity(forText: "Retained") == childIdentity)
      // An open inline menu becomes an open floating menu in the same frame.
      #expect(harness.frame.contains("Retained 1"))
      #expect(probe.starts == 1)
      #expect(probe.cancellations == 0)
      #expect(probe.cancellationSignals.withLock { $0 } == 0)
      _ = try harness.pressKey(KeyPress(.escape))
    }
    #expect(!harness.frame.contains("Retained 1"))
    try await waitForStyleLifetime { probe.cancellations == 1 }
    #expect(harness.activeTaskCount == 0)
    _ = try harness.clickText("Commands")
    try await waitForStyleLifetime { probe.starts == 2 }
    #expect(harness.frame.contains("Retained 1"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.frame.contains("Retained 1"))
    #expect(probe.starts == 2)
    #expect(probe.cancellations == 1)
    #expect(probe.cancellationSignals.withLock { $0 } == 1)
    #expect(harness.activeTaskCount == 1)
    _ = try harness.clickText("Retained 1")
    #expect(harness.frame.contains("Retained 2"))
  }
}

@MainActor private final class StyleLifetimeProbe {
  nonisolated let cancellationSignals = Mutex(0)
  var starts = 0
  var cancellations = 0
}

private struct StyleLifetimeFixture: View {
  @State private var compact = false
  let menu: Bool
  let probe: StyleLifetimeProbe
  var body: some View {
    VStack {
      if menu {
        Menu("Commands") { StyleLifetimeChild(probe: probe) }
          .menuStyle(compact ? AnyMenuStyle.automatic : .inline)
      } else {
        ControlGroup("Commands") { StyleLifetimeChild(probe: probe) }
          .controlGroupStyle(compact ? AnyControlGroupStyle.compactMenu : .horizontal)
      }
    }
    .panel(id: "lifetime")
    .keyCommand("Restyle", key: .character("g"), modifiers: .ctrl) { compact.toggle() }
  }
}

private struct StyleLifetimeChild: View {
  @State private var count = 0
  let probe: StyleLifetimeProbe
  var body: some View {
    Button("Retained \(count)") { count += 1 }
      .task {
        probe.starts += 1
        await withTaskCancellationHandler {
          await suspendUntilCancelled()
        } onCancel: {
          probe.cancellationSignals.withLock { $0 += 1 }
        }
        if Task.isCancelled { probe.cancellations += 1 }
      }
  }
}

@MainActor private func waitForStyleLifetime(_ condition: () -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(3))
  while !condition(), clock.now < deadline { await Task.yield() }
  try #require(condition())
}
