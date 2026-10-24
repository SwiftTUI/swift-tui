@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 task body lifetimes", .serialized)
struct AdversarialSetETaskLifetimeTests {
  @Test(arguments: Array(21...30))
  func taskLifetime(id: Int) async throws {
    let probe = SetETaskProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 48, height: 12)
    ) { SetETaskLifetimeRoot(kind: id, probe: probe) }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.release.fire()
      await probe.changed.wait { probe.finished.count == probe.started.count }
    }
    do {
      let initial = id == 26 || id == 27 ? 2 : 1
      try #require(h.activeTaskCount == initial)
      await probe.changed.wait { probe.started.count == initial }
      switch id {
      case 21:
        for cycle in 1...3 {
          _ = try h.clickText("Toggle")
          #expect(h.activeTaskCount == 0)
          await probe.changed.wait { probe.finished.count == cycle }
          #expect(probe.cancelled.count == cycle)
          if cycle < 3 {
            _ = try h.clickText("Toggle")
            try #require(h.activeTaskCount == 1)
            await probe.changed.wait { probe.started.count == cycle + 1 }
          }
        }
      case 22:
        probe.release.fire()
        await probe.changed.wait { probe.finished.count == 1 }
        #expect(h.activeTaskCount == 0)
        #expect(probe.cancelled.isEmpty)
        for _ in 0..<3 { _ = try h.clickText("Other") }
        #expect(h.activeTaskCount == 0)
        #expect(probe.started.count == 1)
      case 23, 24:
        for generation in 1...3 {
          _ = try h.clickText("Advance")
          try #require(h.activeTaskCount == 1)
          await probe.changed.wait {
            probe.started.count == generation + 1 && probe.finished.count == generation
          }
          #expect(probe.cancelled.count == generation)
          #expect(probe.started.last == "main-\(generation)")
        }
      case 25, 29:
        for _ in 0..<3 { _ = try h.clickText(id == 29 ? "Advance" : "Other") }
        #expect(h.activeTaskCount == 1)
        #expect(probe.started.count == 1)
        #expect(probe.finished.isEmpty)
      case 26:
        #expect(Set(probe.started) == ["first", "second"])
        _ = try h.clickText("Toggle")
        #expect(h.activeTaskCount == 0)
        await probe.changed.wait { probe.finished.count == 2 }
        #expect(Set(probe.cancelled) == ["first", "second"])
      case 27:
        _ = try h.clickText("Advance")
        #expect(h.activeTaskCount == 1)
        await probe.changed.wait { probe.finished.count == 1 }
        #expect(probe.cancelled == ["row-1"])
        #expect(probe.started.count == 2)
        _ = try h.clickText("Toggle")
        await probe.changed.wait { probe.finished.count == 2 }
        #expect(Set(probe.cancelled) == ["row-0", "row-1"])
      case 28:
        for cycle in 1...3 {
          _ = try h.clickText("Advance")
          #expect(h.activeTaskCount == 0)
          await probe.changed.wait { probe.finished.count == cycle }
          #expect(probe.cancelled.count == cycle)
          if cycle < 3 {
            _ = try h.clickText("Advance")
            try #require(h.activeTaskCount == 1)
            await probe.changed.wait { probe.started.count == cycle + 1 }
          }
        }
      default:
        h.shutdown()
        #expect(h.activeTaskCount == 0)
        await probe.changed.wait { probe.finished.count == 1 }
        #expect(probe.cancelled.count == 1)
        _ = try h.clickText("Toggle")
        _ = try h.clickText("Toggle")
        #expect(h.activeTaskCount == 0)
        #expect(h.runLoop.lifecycleCoordinator.refusedStartsAfterShutdownCount > 0)
        #expect(probe.started.count == 1)
      }
      await cleanup()
      #expect(h.activeTaskCount == 0)
      #expect(h.activeTaskDescriptorCount == 0)
      #expect(probe.finished.count == probe.started.count)
    } catch {
      await cleanup()
      throw error
    }
  }
}

@MainActor
private final class SetETaskProbe {
  let changed = MainActorConditionSignal()
  let release = AsyncEvent()
  var started: [String] = []
  var cancelled: [String] = []
  var finished: [String] = []
  func run(_ key: String) async {
    started.append(key)
    changed.notify()
    await release.wait()
    if Task.isCancelled { cancelled.append(key) }
    finished.append(key)
    changed.notify()
  }
}

private struct SetETaskLifetimeRoot: View {
  let kind: Int
  let probe: SetETaskProbe
  @State private var shown = true
  @State private var generation = 0
  @State private var other = 0
  @State private var rowCount = 2
  @State private var selection = 0
  @State private var disabled = false
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack {
        Button("Toggle") { shown.toggle() }
        Button("Advance") {
          generation += 1
          rowCount = 1
          selection = 1 - selection
          disabled.toggle()
        }
        Button("Other") { other += 1 }
      }
      Text("Other \(other)")
      if shown { subject }
    }
  }
  @ViewBuilder private var subject: some View {
    let key = "main-\(generation)"
    switch kind {
    case 23:
      Text("Work").task { await probe.run(key) }.id("owner-\(generation)")
    case 24:
      Text("Work").task(id: generation) { await probe.run(key) }
    case 26:
      Text("Work").task { await probe.run("first") }.task { await probe.run("second") }
    case 27:
      ForEach(0..<rowCount) { row in
        Text("Work \(row)").task { await probe.run("row-\(row)") }
      }
    case 28:
      TabView(selection: $selection) {
        Tab("Work", value: 0) { Text("Active work").task { await probe.run("tab") } }
        Tab("Rest", value: 1) { Text("No task") }
      }.tabViewStyle(.literalTabs)
    case 29:
      Text("Work").task { await probe.run(key) }.disabled(disabled)
    default:
      Text("Work").task { await probe.run(key) }
    }
  }
}
