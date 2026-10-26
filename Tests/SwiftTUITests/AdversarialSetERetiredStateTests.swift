@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two F3 pass 2 (setE123–setE128): writes from retired State owners.
// A body-created closure whose owner was removed, with no occupant at its
// identity, must not reach a later mount (State-Keying.md, STUI-1173/1241).
// 128 pins the ratified refresh tier: after a remount the closure reaches the
// live occupant (Divergences-And-Gaps.md, "State ownership is bound at capture").

@MainActor
@Suite("Campaign F3 pass 2 retired State owners", .serialized)
struct AdversarialSetERetiredStateTests {
  @Test(arguments: Array(123...128))
  func retiredOwnerWrite(id: Int) async throws {
    let probe = SetERetiredProbe()
    let model = SetERetiredModel()
    let root = testIdentity("setE", String(id))
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 40, height: 10)) {
      SetERetiredRoot(kind: id, model: model, probe: probe)
    }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.releaseAll()
      await probe.changed.wait { probe.finished == probe.started }
    }
    do {
      try #require(h.frame.contains("value 0"), "\(h.frame)")
      if id == 123 {
        await probe.changed.wait { probe.started == 1 }
      }
      let writer = try #require(probe.writer)
      // Remove the owner (125 dismisses the sheet). 124's onDisappear writes
      // during this frame; 123's cancelled body resumes and writes after it.
      switch id {
      case 123:
        try await withRetiredWriteAccountingAsync {
          model.shown = false
          _ = try h.renderAfterExternalMutation()
          await probe.changed.wait { probe.finished == 1 }
        }
      case 124:
        try withRetiredWriteAccounting {
          model.shown = false
          _ = try h.renderAfterExternalMutation()
        }
        #expect(probe.disappearWrites == 1)
      default:
        model.shown = false
        _ = try h.renderAfterExternalMutation()
      }
      try #require(!h.frame.contains("value"), "\(h.frame)")
      switch id {
      case 128:
        model.shown = true
        _ = try h.renderAfterExternalMutation()
        try #require(h.frame.contains("value 0"), "\(h.frame)")
        writer(5)
        _ = try h.render()
        #expect(h.frame.contains("value 5"), "the ratified refresh missed: \(h.frame)")
      case 125, 126, 127:
        try withRetiredWriteAccounting { writer(9) }
      default:
        break
      }
      if id != 128 {
        model.shown = true
        _ = try h.renderAfterExternalMutation()
        #expect(h.frame.contains("value 0"), "a retired write seeded the remount: \(h.frame)")
        #expect(!h.frame.contains("value 9"))
      }
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }
}

/// Retired writes record a seed-fallback runtime issue and the seed-fallback
/// and capture-miss soundness counters (State.swift). Assert and restore them
/// locally, as setC006 does, so the soundness gate still rejects any other
/// diagnostic from the fixture.
@MainActor
private func withRetiredWriteAccounting(_ body: () throws -> Void) throws {
  let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
  let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
  let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
  SoundnessProbeConfiguration.isTraceEnabled = false
  defer {
    SoundnessProbeConfiguration.isTraceEnabled = savedTrace
    SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
    SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
  }
  _ = ImperativeRuntimeIssueQueue.drain()
  try body()
  let issues = ImperativeRuntimeIssueQueue.drain().filter {
    $0.code == "state.imperativeSeedFallback"
  }
  #expect(issues.allSatisfy { $0.message.contains("discarded") }, "\(issues.map(\.message))")
}

@MainActor
private func withRetiredWriteAccountingAsync(_ body: () async throws -> Void) async throws {
  let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
  let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
  let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
  SoundnessProbeConfiguration.isTraceEnabled = false
  defer {
    SoundnessProbeConfiguration.isTraceEnabled = savedTrace
    SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
    SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
  }
  _ = ImperativeRuntimeIssueQueue.drain()
  try await body()
  let issues = ImperativeRuntimeIssueQueue.drain().filter {
    $0.code == "state.imperativeSeedFallback"
  }
  #expect(issues.allSatisfy { $0.message.contains("discarded") }, "\(issues.map(\.message))")
}

@MainActor
private final class SetERetiredModel {
  var shown = true
  var binding: Binding<Bool> {
    Binding(get: { self.shown }, set: { self.shown = $0 })
  }
}

@MainActor
private final class SetERetiredProbe {
  let changed = MainActorConditionSignal()
  var writer: ((Int) -> Void)?
  var disappearWrites = 0
  private(set) var started = 0
  private(set) var finished = 0
  private var releases: [Int: AsyncEvent] = [:]

  func stash(_ write: @escaping (Int) -> Void) {
    if writer == nil { writer = write }
  }

  private func event(_ generation: Int) -> AsyncEvent {
    if let event = releases[generation] { return event }
    let event = AsyncEvent()
    releases[generation] = event
    return event
  }

  func begin() -> Int {
    started += 1
    changed.notify()
    return started
  }

  func waitForRelease(_ generation: Int) async {
    await event(generation).wait()
  }

  func release(generation: Int) {
    event(generation).fire()
  }

  func end() {
    finished += 1
    changed.notify()
  }

  func releaseAll() {
    for generation in 1...max(1, started) { release(generation: generation) }
  }
}

private struct SetERetiredRoot: View {
  let kind: Int
  let model: SetERetiredModel
  let probe: SetERetiredProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root")
      switch kind {
      case 125:
        Button("Opener") {}.sheet(isPresented: model.binding) {
          SetERetiredLeaf(kind: kind, probe: probe)
        }
      case 126:
        if model.shown { Text("Subject").modifier(SetERetiredModifier(probe: probe)) }
      case 127:
        if model.shown { SetERetiredPropertyLeaf(probe: probe) }
      default:
        if model.shown { SetERetiredLeaf(kind: kind, probe: probe) }
      }
    }
  }
}

private struct SetERetiredLeaf: View {
  let kind: Int
  let probe: SetERetiredProbe
  @State private var value = 0

  var body: some View {
    let _ = probe.stash { value = $0 }
    let label = Text("value \(value)")
    switch kind {
    case 123:
      label.task {
        let generation = probe.begin()
        await probe.waitForRelease(generation)
        // Deliberately ignores cancellation: the write lands after removal.
        if generation == 1 { value = 9 }
        probe.end()
      }
    case 124:
      label.onDisappear {
        value = 9
        probe.disappearWrites += 1
      }
    default:
      label
    }
  }
}

private struct SetERetiredModifier: ViewModifier {
  let probe: SetERetiredProbe
  @State private var value = 0

  func body(content: Content) -> some View {
    let _ = probe.stash { value = $0 }
    VStack(alignment: .leading, spacing: 0) {
      content
      Text("value \(value)")
    }
  }
}

private struct SetERetiredCounter: DynamicProperty {
  @State var value = 0
}

private struct SetERetiredPropertyLeaf: View {
  let probe: SetERetiredProbe
  var counter = SetERetiredCounter()

  var body: some View {
    let _ = probe.stash { counter.value = $0 }
    Text("value \(counter.value)")
  }
}
