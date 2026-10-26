@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two F3 pass 2 (setE101–setE108): departing content under a held
// focus re-render. A pass that commits and then re-renders once for focus
// cancels the tasks it removed at its own commit (Runtime.md, STUI-1233).
// Each scenario holds raster entry 2, the re-render's tail, and wakes the
// departed body through a producer-owned tick while the re-render is held.

@MainActor
@Suite("Campaign F3 pass 2 departure under a held focus re-render", .serialized)
struct AdversarialSetEDepartureCarryTests {
  @Test(arguments: Array(101...108))
  func focusRerenderDeparture(id: Int) async throws {
    let model = SetEDepartureModel()
    let probe = SetETickProbe()
    let root = testIdentity("setE", String(id))
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 48, height: 12)) {
      SetEDepartureRoot(kind: id, model: model, probe: probe)
    }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.finishAll()
      await probe.changed.wait { probe.running == 0 }
    }
    do {
      let baseline = setECensus(h)
      let baselineTasks = h.activeTaskCount
      let cycles = id == 108 ? 3 : 1
      var mounted: [String: Int]?
      for cycle in 1...cycles {
        try mount(id: id, model: model, h: h)
        if id == 105 {
          // One disappear per lifetime, after removal: none at mount.
          #expect(probe.disappears == cycle - 1, "onDisappear ran when the content mounted")
        }
        let keys = SetEDepartureRoot.departingKeys(kind: id)
        let expectedStarts = (keys + SetEDepartureRoot.survivingKeys(kind: id)).count * cycle
        if id != 108 {
          await probe.changed.wait { probe.starts.count >= expectedStarts }
          try #require(probe.starts.count == expectedStarts)
        }
        let current = setECensus(h)
        if let mounted { #expect(current == mounted) } else { mounted = current }
        _ = try h.focusText("Bump")
        let mountedTasks = h.activeTaskCount
        try #require(mountedTasks > baselineTasks)
        let endsBefore = probe.ends.count
        let cancelledBefore = h.runLoop.cancelledRenderCount
        let gated = try await setEGatedRender(h, root: root, blockingEntry: 2) {
          SetEDepartureRoot.depart(kind: id, model: model)
        } whileHeld: {
          probe.departed = true
          for key in keys {
            await probe.tick(key).wait()
          }
          #expect(probe.iterationsAfterDeparture == 0, "a departed task ran during the hold")
          for key in keys {
            #expect(probe.cancelled.contains(key), "\(key) still running at the hold")
          }
          if id == 104 {
            await probe.tick("row-0").wait()
            #expect(probe.iterations["row-0", default: 0] == 1)
            #expect(!probe.ends.contains("row-0"))
          }
          if id == 105 {
            // A superseded re-render runs the carried disappear at once
            // (Runtime.md:123-126); a held one runs it after the frame
            // presents (Runtime.md:120-122). The task was cancelled first.
            let superseded = h.runLoop.cancelledRenderCount > cancelledBefore
            #expect(probe.disappears == (superseded ? cycle : cycle - 1))
          }
          if id == 108 {
            #expect(h.activeTaskCount == baselineTasks)
          }
        }
        try #require(gated.blocked, "the departure did not re-render for focus")
        // Premise: entry 2 was the departure frame's own focus re-render. A
        // ForEach row removal converges without an eager re-render, so 104
        // holds the following frame instead (corrections.md).
        if id != 104 {
          try #require(gated.frames == 1, "entry 2 belonged to a later frame (\(gated.frames))")
        }
        probe.departed = false
        await probe.changed.wait { probe.ends.count >= endsBefore + keys.count }
        #expect(probe.ends.count == endsBefore + keys.count)
        #expect(h.activeTaskCount == mountedTasks - (id == 108 ? 1 : keys.count))
        if id == 105 { #expect(probe.disappears == cycle) }
        if SetEDepartureRoot.survivingKeys(kind: id).isEmpty {
          #expect(setECensus(h) == baseline)
        }
        SetEDepartureRoot.reset(kind: id, model: model)
        _ = try h.renderAfterExternalMutation()
      }
      await cleanup()
      #expect(h.activeTaskCount == 0)
    } catch {
      await cleanup()
      throw error
    }
  }

  private func mount(
    id: Int, model: SetEDepartureModel, h: StressRuntimeHarness<SetEDepartureRoot>
  ) throws {
    switch id {
    case 106: model.isPresented = true
    case 107: model.path = [1]
    default: model.shown = true
    }
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Bump"), "\(h.frame)")
  }
}

/// Renders the pending frames through the async driver while `blockingEntry`
/// raster entry is held. `mutate` runs before the render starts; `whileHeld`
/// runs on the main actor while the entry is blocked. Returns whether the
/// gate was reached (a premise failure finishes the render instead of hanging).
@MainActor
func setEGatedRender<Content: View>(
  _ h: StressRuntimeHarness<Content>,
  root: Identity,
  blockingEntry: Int,
  mutate: () -> Void,
  whileHeld: () async -> Void
) async throws -> (blocked: Bool, frames: Int) {
  let gate = AsyncFrameTailBlockingGate(blockingEntry: blockingEntry)
  h.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
  defer {
    gate.release()
    h.runLoop.renderer.setFrameTailRenderHooks(nil)
  }
  let pump = SwiftTUIRuntime.RunLoop<Int, Content>.EventPump(
    stream: AsyncStream { $0.finish() }, drainEvents: { [] }, hasPendingEvents: { false },
    cancel: {}, scheduleDeadlineWake: { _ in })
  mutate()
  h.runLoop.scheduler.requestInvalidation(of: [root])
  let finished = AsyncEvent()
  let renderTask = Task { @MainActor in
    var frames = 0
    _ = try await h.runLoop.renderPendingFramesAsync(renderedFrames: &frames, eventPump: pump)
    finished.fire()
    return frames
  }
  let blocked = await firstFrameTailSignal(blocked: gate, orFinished: finished)
  if blocked { await whileHeld() }
  gate.release()
  return (blocked, try await renderTask.value)
}

/// Producer-owned signals for `.task` tick loops keyed by name: each start
/// announces itself, each tick fires once the loop consumed it or ended, and
/// each loop records how it ended.
@MainActor
final class SetETickProbe {
  let changed = MainActorConditionSignal()
  var departed = false
  var disappears = 0
  private(set) var starts: [String] = []
  private(set) var ends: [String] = []
  private(set) var cancelled: [String] = []
  private(set) var iterations: [String: Int] = [:]
  private(set) var iterationsAfterDeparture = 0
  private var continuations: [String: AsyncStream<Void>.Continuation] = [:]
  private var pendingTicks: [String: AsyncEvent] = [:]

  var running: Int { starts.count - ends.count }

  func start(_ key: String) -> AsyncStream<Void> {
    starts.append(key)
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    continuations[key] = continuation
    changed.notify()
    return stream
  }

  func iterate(_ key: String) {
    iterations[key, default: 0] += 1
    if departed { iterationsAfterDeparture += 1 }
    pendingTicks.removeValue(forKey: key)?.fire()
  }

  func end(_ key: String, cancelled wasCancelled: Bool) {
    ends.append(key)
    if wasCancelled { cancelled.append(key) }
    continuations[key] = nil
    pendingTicks.removeValue(forKey: key)?.fire()
    changed.notify()
  }

  /// Fires once the running loop consumed the tick or ended; at once when
  /// no loop with this key is running.
  func tick(_ key: String) -> AsyncEvent {
    let event = AsyncEvent()
    guard let continuation = continuations[key] else {
      event.fire()
      return event
    }
    pendingTicks[key] = event
    continuation.yield(())
    return event
  }

  func finishAll() {
    for continuation in continuations.values { continuation.finish() }
  }
}

@MainActor
private final class SetEDepartureModel {
  var shown = false
  var isPresented = false
  var path: [Int] = []
  var rows = 2
  var presentedBinding: Binding<Bool> {
    Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
  }
  var pathBinding: Binding<[Int]> {
    Binding(get: { self.path }, set: { self.path = $0 })
  }
}

private struct SetEDepartureRoot: View {
  let kind: Int
  let model: SetEDepartureModel
  let probe: SetETickProbe

  static func departingKeys(kind: Int) -> [String] {
    switch kind {
    case 102: ["first", "second"]
    case 104: ["row-1"]
    case 108: []
    default: ["main"]
    }
  }

  static func survivingKeys(kind: Int) -> [String] {
    kind == 104 ? ["row-0"] : []
  }

  @MainActor static func depart(kind: Int, model: SetEDepartureModel) {
    switch kind {
    case 104: model.rows = 1
    case 106: model.isPresented = false
    case 107: model.path = []
    default: model.shown = false
    }
  }

  @MainActor static func reset(kind: Int, model: SetEDepartureModel) {
    model.rows = 2
    if kind == 104 { model.shown = false }
  }

  var body: some View {
    switch kind {
    case 106:
      VStack(alignment: .leading, spacing: 0) {
        Button("Opener") {}
      }
      .sheet(isPresented: model.presentedBinding) {
        SetEDepartingContent(kind: kind, key: "main", probe: probe)
      }
    case 107:
      NavigationStack(path: model.pathBinding) {
        VStack(alignment: .leading, spacing: 0) {
          Button("Home") {}
        }
        .navigationDestination(for: Int.self) { _ in
          SetEDepartingContent(kind: kind, key: "main", probe: probe)
        }
      }
    default:
      VStack(alignment: .leading, spacing: 0) {
        Button("Persistent") {}
        if model.shown {
          if kind == 104 {
            ForEach(0..<model.rows, id: \.self) { row in
              SetEDepartingContent(kind: kind, key: "row-\(row)", probe: probe)
            }
          } else {
            SetEDepartingContent(kind: kind, key: "main", probe: probe)
          }
        }
      }
    }
  }
}

private struct SetEDepartingContent: View {
  let kind: Int
  let key: String
  let probe: SetETickProbe
  @State private var count = 0

  private var label: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(key) count \(count)")
      if kind != 104 || key == "row-1" {
        Button("Bump") { count += 1 }
      }
    }
  }

  private func loop(_ name: String) async {
    let ticks = probe.start(name)
    for await _ in ticks {
      count += 1
      probe.iterate(name)
    }
    probe.end(name, cancelled: Task.isCancelled)
  }

  var body: some View {
    switch kind {
    case 102:
      label.task { await loop("first") }.task { await loop("second") }
    case 103:
      label.task(id: 7) { await loop(key) }
    case 105:
      label.onDisappear { probe.disappears += 1 }.task { await loop(key) }
    case 108:
      TimelineView(.periodic(by: .seconds(3600))) { _ in label }
    default:
      label.task { await loop(key) }
    }
  }
}
