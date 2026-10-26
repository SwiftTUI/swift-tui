@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two F3 pass 2 (setE114–setE122): lifecycle handlers carried past a
// focus re-render. 114–117 mount a view in a committed pass and remove it in
// that pass's own focus re-render (not superseded); 118–122 open a
// presentation and dismiss it while the open's raster entry 1 is held, so the
// re-render is superseded (STUI-1234's shape, other presentation kinds).

@MainActor
@Suite("Campaign F3 pass 2 carried lifecycle handlers", .serialized)
struct AdversarialSetECarriedHandlerTests {
  static let newOne =
    "NEW-1: a view mounted by a committed pass and removed by that pass's own focus re-render gets onDisappear without onAppear (appear skipped, initial onChange runs on the retired owner); the carried plan dispatches after the re-render commit, and LifecycleCoordinator.apply looks appear handlers up only in the current registry; contract: Runtime.md:117-122, LifecycleCoordinator.swift:48-55 skip zero-oracle; adjacent STUI-1234"
  static let newTwo =
    "NEW-2: a child view whose body applies .onChange or .task inside a switch branch to an .onAppear/.onDisappear-modified view runs onDisappear once when it mounts, before onAppear; suspected chain-collapse absorbed-interior reclaim (ViewGraphChainCollapse.swift:27-95) plans the interior's disappear; contract: SwiftUI onAppear/onDisappear pairing, Runtime.md:117-118; adjacent STUI-1174"

  @Test(arguments: Array(114...117))
  func carriedHandler(id: Int) async throws {
    let probe = SetECarryProbe()
    let model = SetECarryModel()
    let root = testIdentity("setE", String(id))
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 48, height: 12)) {
      SetEHintRoot(kind: id, model: model, probe: probe)
    }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.release.fire()
      await probe.changed.wait { probe.taskEnds == probe.taskStarts }
    }
    do {
      if id == 115 || id == 116 {
        try await mountControl(id: id)
      }
      let coordinator = h.runLoop.lifecycleCoordinator
      let appearSkips = coordinator.appearHandlerSkipCount
      let disappearSkips = coordinator.disappearHandlerSkipCount
      let changeSkips = coordinator.changeHandlerSkipCount
      let changeFallbacks = coordinator.changeHandlerSnapshotFallbackCount
      let startSkips = coordinator.taskStartSkipCount
      let baselineTasks = h.activeTaskCount
      if id == 117 {
        model.isPresented = true
        _ = try h.renderAfterExternalMutation()
      } else {
        _ = try h.focusText("Open")
        _ = try h.pressKey(.init(.return))
      }
      // Premise: focus entered the field and its re-render removed the hint,
      // which the committed pass had mounted (its disappear ran).
      try #require(h.frame.contains("Name"), "\(h.frame)")
      try #require(!h.frame.contains("Hint"), "\(h.frame)")
      try #require(probe.disappears >= 1, "hint lifecycle: \(probe.events)")
      // One lifetime: one appear (landed), then one disappear.
      setEKnown(Self.newOne) {
        #expect(probe.appears == 1, "onDisappear ran without onAppear: \(probe.events)")
        #expect(probe.appearLanded == [true])
        #expect(coordinator.appearHandlerSkipCount == appearSkips)
      }
      if id == 115 || id == 116 {
        setEKnown(Self.newTwo) {
          #expect(probe.disappears == 1, "hint lifecycle: \(probe.events)")
        }
      } else {
        #expect(probe.disappears == 1, "hint lifecycle: \(probe.events)")
      }
      switch id {
      case 115:
        setEKnown(Self.newOne) {
          #expect(probe.changeLanded == [true], "\(probe.changeLanded)")
          #expect(coordinator.changeHandlerSnapshotFallbackCount == changeFallbacks)
        }
        #expect(coordinator.changeHandlerSkipCount == changeSkips)
      case 116:
        #expect(h.activeTaskCount == baselineTasks)
        #expect(coordinator.taskStartSkipCount == startSkips)
        #expect(probe.taskStarts == probe.taskEnds)
      default:
        break
      }
      #expect(coordinator.disappearHandlerSkipCount == disappearSkips)
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }

  /// The same hint mounted and removed in separate frames with no focus
  /// re-render: one appear at mount, one disappear at removal.
  private func mountControl(id: Int) async throws {
    let probe = SetECarryProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", "\(id)-control"), size: .init(width: 40, height: 8)
    ) { SetEHintToggleRoot(kind: id, probe: probe) }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.release.fire()
      await probe.changed.wait { probe.taskEnds == probe.taskStarts }
    }
    do {
      _ = try h.clickText("Show")
      try #require(h.frame.contains("Hint"), "\(h.frame)")
      #expect(probe.appears == 1)
      setEKnown(Self.newTwo) {
        #expect(probe.disappears == 0, "onDisappear ran when the hint mounted: \(probe.events)")
      }
      _ = try h.clickText("Hide")
      setEKnown(Self.newTwo) {
        #expect(probe.disappears == 1, "\(probe.events)")
      }
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }

  @Test(arguments: Array(118...122))
  func supersededOpen(id: Int) async throws {
    let probe = SetECarryProbe()
    let model = SetECarryModel()
    let root = testIdentity("setE", String(id))
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 60, height: 16)) {
      SetESupersededRoot(kind: id, model: model, probe: probe)
    }
    @MainActor func cleanup() async {
      h.shutdown()
      probe.release.fire()
      await probe.changed.wait { probe.taskEnds == probe.taskStarts }
    }
    do {
      let coordinator = h.runLoop.lifecycleCoordinator
      let appearSkips = coordinator.appearHandlerSkipCount
      let changeSkips = coordinator.changeHandlerSkipCount
      let startSkips = coordinator.taskStartSkipCount
      let baseline = setECensus(h)
      let marker = id == 122 ? "Filter commands" : "Probe filter"
      for cycle in 1...(id == 122 ? 3 : 1) {
        let gated = try await setEGatedRender(h, root: root, blockingEntry: 1) {
          model.isPresented = true
        } whileHeld: {
          model.isPresented = false
          h.runLoop.scheduler.requestInvalidation(of: [root])
        }
        try #require(gated.blocked, "the open never reached its frame tail")
        #expect(!h.frame.contains(marker), "\(h.frame)")
        #expect(coordinator.appearHandlerSkipCount == appearSkips)
        #expect(coordinator.changeHandlerSkipCount == changeSkips)
        #expect(coordinator.taskStartSkipCount == startSkips)
        if id == 122 {
          #expect(setECensus(h) == baseline, "cycle \(cycle)")
        } else {
          #expect(probe.appears == 1, "the open's appear handler did not run")
          #expect(probe.disappears == probe.appears)
          #expect(probe.appearLanded == [true], "\(probe.appearLanded)")
        }
        if id == 121 {
          await probe.changed.wait { probe.taskEnds == probe.taskStarts }
          #expect(h.activeTaskCount == baseline["taskBodies", default: 0])
        }
      }
      await cleanup()
    } catch {
      await cleanup()
      throw error
    }
  }
}

@MainActor
private final class SetECarryModel {
  var isPresented = false
  var binding: Binding<Bool> {
    Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
  }
}

@MainActor
private final class SetECarryProbe {
  let changed = MainActorConditionSignal()
  let release = AsyncEvent()
  var appears = 0
  var disappears = 0
  var appearLanded: [Bool] = []
  var changeLanded: [Bool] = []
  var taskStarts = 0
  var taskEnds = 0
  var events: [String] = []

  func runTask() async {
    events.append("task")
    taskStarts += 1
    changed.notify()
    await release.wait()
    taskEnds += 1
    changed.notify()
  }
}

/// 114–116: the Open button removes itself, focus re-seats into the field and
/// the field's `@FocusState` flip removes the hint in the eager re-render.
/// 117: the same hint inside sheet content whose field takes default focus.
private struct SetEHintRoot: View {
  let kind: Int
  let model: SetECarryModel
  let probe: SetECarryProbe
  @State private var opened = false

  var body: some View {
    if kind == 117 {
      Text("Workspace").sheet(isPresented: model.binding) {
        SetEHintField(kind: kind, probe: probe, scoped: true)
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        if !opened { Button("Open") { opened = true } }
        if opened { SetEHintField(kind: kind, probe: probe, scoped: false) }
      }
    }
  }
}

private struct SetEHintToggleRoot: View {
  let kind: Int
  let probe: SetECarryProbe
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Show") { shown = true }
      Button("Hide") { shown = false }
      if shown { SetEHint(kind: kind, probe: probe) }
    }
  }
}

private struct SetEHintField: View {
  let kind: Int
  let probe: SetECarryProbe
  let scoped: Bool
  @State private var text = ""
  @FocusState private var isFieldFocused: Bool
  @Namespace private var scope

  var body: some View {
    if scoped {
      VStack(alignment: .leading, spacing: 0) {
        TextField("Name", text: $text)
          .focused($isFieldFocused)
          .prefersDefaultFocus(in: scope)
        if !isFieldFocused { SetEHint(kind: kind, probe: probe) }
      }
      .focusScope(scope)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        TextField("Name", text: $text).focused($isFieldFocused)
        if !isFieldFocused { SetEHint(kind: kind, probe: probe) }
      }
    }
  }
}

private struct SetEHint: View {
  let kind: Int
  let probe: SetECarryProbe
  @State private var mark = -1

  private func stamp(_ value: Int) -> Bool {
    mark = value
    return mark == value
  }

  var body: some View {
    let hint = Text("Hint")
      .onAppear {
        probe.events.append("appear")
        probe.appears += 1
        probe.appearLanded.append(stamp(1))
      }
      .onDisappear {
        probe.events.append("disappear")
        probe.disappears += 1
      }
    switch kind {
    case 115:
      hint.onChange(of: kind, initial: true) {
        probe.events.append("change")
        probe.changeLanded.append(stamp(2))
      }
    case 116:
      hint.task { await probe.runTask() }
    default:
      hint
    }
  }
}

/// 118–121: a presentation whose filter takes default focus on open, so the
/// open commits and re-renders for focus; 122: the default command palette.
private struct SetESupersededRoot: View {
  let kind: Int
  let model: SetECarryModel
  let probe: SetECarryProbe

  var body: some View {
    let base = Text("Workspace")
    switch kind {
    case 119:
      base.fullScreenCover(isPresented: model.binding) {
        SetESupersededBody(kind: kind, probe: probe)
      }
    case 120:
      base.popover(isPresented: model.binding) { SetESupersededBody(kind: kind, probe: probe) }
    case 122:
      Panel(id: "setE122-source") { Text("Workspace") }
        .paletteCommand(name: "Alpha") {}
        .paletteCommand(name: "Beta") {}
        .panel(id: "setE122-host")
        .paletteSheet("Command palette", isPresented: model.binding)
    default:
      base.sheet(isPresented: model.binding) { SetESupersededBody(kind: kind, probe: probe) }
    }
  }
}

private struct SetESupersededBody: View {
  let kind: Int
  let probe: SetECarryProbe
  @State private var query = "seed"
  @State private var mark = -1
  @FocusState private var isQueryFocused: Bool
  @Namespace private var filterScope

  private func stamp() -> Bool {
    mark = probe.appears
    return mark == probe.appears
  }

  var body: some View {
    let content = VStack(alignment: .leading, spacing: 0) {
      TextField("Probe filter", text: $query)
        .focused($isQueryFocused)
        .prefersDefaultFocus(in: filterScope)
      Text("Body")
    }
    .focusScope(filterScope)
    .onAppear {
      probe.appears += 1
      probe.appearLanded.append(stamp())
    }
    .onDisappear { probe.disappears += 1 }
    if kind == 121 {
      content.task { await probe.runTask() }
    } else {
      content
    }
  }
}
