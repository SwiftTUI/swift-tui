@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Viewport lifecycle ownership migration", .serialized, .timeLimit(.minutes(1)))
struct ViewportLifecycleMigrationTests {
  @Test(
    "flattening preserves state and lifecycle; only changed task IDs restart",
    arguments: [false, true])
  func flatteningPreservesMountedRow(changesTaskID: Bool) async throws {
    let probe = MigrationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["ViewportMigration"]),
      size: .init(width: 40, height: 10)
    ) {
      MigrationList(probe: probe, changesTaskID: changesTaskID)
    }
    defer { harness.shutdown() }
    try await waitForMigration { probe.starts == 1 }
    #expect(probe.appears == 1)
    let identity = try #require(harness.runLoop.localTaskRegistry.snapshot().keys.first)
    var nodeID = try #require(
      harness.runLoop.renderer.viewGraph.nodeForIdentity(identity)?.viewNodeID)
    for count in 0..<6 {
      try harness.clickText("Toggle row \(count)")
      let currentID = try #require(
        harness.runLoop.renderer.viewGraph.nodeForIdentity(identity)?.viewNodeID)
      #expect(currentID != nodeID)
      nodeID = currentID
      let starts = changesTaskID ? (count + 1) / 2 + 1 : 1
      try await waitForMigration { probe.starts == starts && probe.cancellations == starts - 1 }
      #expect(harness.frame.contains("Toggle row \(count + 1)"))
      #expect(probe.appears == 1)
      #expect(probe.disappears == 0)
      #expect(probe.starts == starts)
      #expect(probe.cancellations == starts - 1)
      #expect(probe.cancellationSignals.withLock { $0 } == starts - 1)
      #expect(harness.activeTaskCount == 1)
    }
    try harness.clickText("Remove row")
    let finalStarts = changesTaskID ? 4 : 1
    try await waitForMigration { probe.cancellations == finalStarts }
    #expect(probe.disappears == 1)
    #expect(probe.starts == finalStarts)
    #expect(harness.activeTaskCount == 0)
    #expect(probe.cancellationSignals.withLock { $0 } == finalStarts)
  }
}

@MainActor
private final class MigrationProbe {
  nonisolated let cancellationSignals = Mutex(0)
  var appears = 0
  var disappears = 0
  var starts = 0
  var cancellations = 0
}

@MainActor
private struct MigrationList: View {
  let probe: MigrationProbe
  let changesTaskID: Bool
  @State private var showsRow = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remove row") { showsRow = false }
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<(showsRow ? 1 : 0), id: \.self) { _ in
            MigrationRow(probe: probe, changesTaskID: changesTaskID)
          }
        }
      }
      .frame(width: 38, height: 6, alignment: .topLeading)
    }
  }
}

@MainActor
private struct MigrationRow: View {
  let probe: MigrationProbe
  let changesTaskID: Bool
  @State private var expanded = false

  var body: some View {
    MigrationCell(expanded: $expanded, probe: probe, changesTaskID: changesTaskID)
    if expanded {
      Text("Expanded detail")
    }
  }
}

@MainActor
private struct MigrationCell: View {
  @Binding var expanded: Bool
  let probe: MigrationProbe
  let changesTaskID: Bool
  @State private var count = 0

  var body: some View {
    Button("Toggle row \(count)") {
      count += 1
      expanded.toggle()
    }
    .onAppear { probe.appears += 1 }
    .onDisappear { probe.disappears += 1 }
    .task(id: changesTaskID ? count / 2 : 0) {
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

@MainActor
private func waitForMigration(_ condition: () -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(3))
  while !condition(), clock.now < deadline {
    await Task.yield()
  }
  try #require(condition())
}
