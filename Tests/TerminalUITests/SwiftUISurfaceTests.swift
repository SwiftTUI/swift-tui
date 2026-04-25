import TerminalUICharts
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private struct PaletteRow: Identifiable {
  let id: String
  let label: String
}

private struct SampleTheme: Equatable, Sendable {
  let accent: String
  let emphasis: String
}

private enum SampleThemeKey: EnvironmentKey {
  static let defaultValue = SampleTheme(
    accent: "default-accent",
    emphasis: "default-emphasis"
  )
}

private enum SurfaceNameKey: EnvironmentKey {
  static let defaultValue = "unset"
}

extension EnvironmentValues {
  fileprivate var sampleTheme: SampleTheme {
    get { self[SampleThemeKey.self] }
    set { self[SampleThemeKey.self] = newValue }
  }

  fileprivate var surfaceName: String {
    get { self[SurfaceNameKey.self] }
    set { self[SurfaceNameKey.self] = newValue }
  }
}

private enum RaisedCenterAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int {
    context[VerticalAlignment.center]
  }
}

extension VerticalAlignment {
  fileprivate static let raisedCenter = Self(RaisedCenterAlignmentID.self)
}

private enum GapAfterKey: LayoutValueKey {
  static let defaultValue = 0
}

private struct GappedRowLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let totalWidth = sizes.enumerated().reduce(0) { partial, entry in
      let gap = entry.offset < subviews.count - 1 ? subviews[entry.offset][GapAfterKey.self] : 0
      return partial + entry.element.width + gap
    }

    return .init(
      width: totalWidth,
      height: sizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    var x = bounds.origin.x

    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      x += size.width

      if index < subviews.count - 1 {
        x += subview[GapAfterKey.self]
      }
    }
  }
}

private struct RaisedGuideReadingLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard subviews.count == 2 else {
      return .zero
    }

    let first = subviews[0].dimensions(in: .unspecified)
    let second = subviews[1].sizeThatFits(.unspecified)
    return .init(
      width: max(first.width, first[.raisedCenter] + second.width),
      height: max(first.height, second.height)
    )
  }

  func placeSubviews(
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard subviews.count == 2 else {
      return
    }

    let firstSize = subviews[0].sizeThatFits(.unspecified)
    let firstDimensions = subviews[0].dimensions(in: .unspecified)
    let secondSize = subviews[1].sizeThatFits(.unspecified)

    subviews[0].place(
      at: .init(x: 0, y: 0),
      anchor: .topLeading,
      proposal: .init(width: firstSize.width, height: firstSize.height)
    )
    subviews[1].place(
      at: .init(x: firstDimensions[.raisedCenter], y: 0),
      anchor: .topLeading,
      proposal: .init(width: secondSize.width, height: secondSize.height)
    )
  }
}

private final class LayoutCacheCounter: Sendable {
  private struct State: Sendable {
    var makeCalls = 0
    var lastMeasuredCache = 0
    var lastPlacedCache = 0
  }

  private let state = LockedBox(State())

  var makeCalls: Int {
    state.value.makeCalls
  }

  var lastMeasuredCache: Int {
    state.value.lastMeasuredCache
  }

  var lastPlacedCache: Int {
    state.value.lastPlacedCache
  }

  func nextMakeCallCount() -> Int {
    state.withLock { state in
      state.makeCalls += 1
      return state.makeCalls
    }
  }

  func recordMeasuredCache(_ cache: Int) {
    state.withLock { $0.lastMeasuredCache = cache }
  }

  func recordPlacedCache(_ cache: Int) {
    state.withLock { $0.lastPlacedCache = cache }
  }
}

private struct CacheTrackingLayout: Layout {
  let counter: LayoutCacheCounter

  func makeCache(subviews _: LayoutSubviews) -> Int {
    counter.nextMakeCallCount()
  }

  func updateCache(
    _ cache: inout Int,
    subviews _: LayoutSubviews
  ) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) -> LayoutSize {
    counter.recordMeasuredCache(cache)
    return subviews.first?.sizeThatFits(.unspecified) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) {
    counter.recordPlacedCache(cache)
    guard let subview = subviews.first else {
      return
    }

    let size = subview.sizeThatFits(.unspecified)
    subview.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(width: size.width, height: size.height)
    )
  }
}

private final class SharedLayoutCacheRecorder: Sendable {
  private let placedValuesStorage = LockedBox<[Int]>([])

  var placedValues: [Int] {
    placedValuesStorage.value
  }

  func appendPlacedValue(_ value: Int) {
    placedValuesStorage.withLock { $0.append(value) }
  }
}

private struct WidthStampingLayout: Layout {
  let recorder: SharedLayoutCacheRecorder

  func makeCache(subviews _: LayoutSubviews) -> Int {
    0
  }

  func updateCache(
    _ cache: inout Int,
    subviews _: LayoutSubviews
  ) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) -> LayoutSize {
    let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
    cache = size.width
    return size
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Int
  ) {
    recorder.appendPlacedValue(cache)
    guard let subview = subviews.first else {
      return
    }

    let size = subview.sizeThatFits(.unspecified)
    subview.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(width: size.width, height: size.height)
    )
  }
}

private struct BodyBasedBadge: View {
  let title: String

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      Text("•")
        .foregroundStyle(.info)
      Text(title)
        .bold()
    }
  }
}

private struct BodyBasedCard: View {
  let title: String
  let value: String

  var body: some View {
    GroupBox(title) {
      BodyBasedBadge(title: value)
    }
  }
}

private struct BodyBasedStatefulCounter: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Count \(count)")
      Button(
        "Increment",
        action: {
          count += 1
        })
    }
  }
}

private struct BodyBasedStatefulField: View {
  @State private var value = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("Name", text: $value)
        .frame(width: 12, alignment: .leading)
      Text("Name: \(value)")
    }
  }
}

@MainActor
@Suite(.serialized)
struct SwiftUISurfaceTests {
  @Test("ViewBuilder flattens Group and drops EmptyView during container resolution")
  func builderFlattensStructuralContent() {
    let includeMiddle = true
    let root = VStack(spacing: 1) {
      Text("Top")
      if includeMiddle {
        Text("Middle")
      }
      Group {
        Text("A")
        EmptyView()
        Text("B")
      }
    }

    let resolved = Resolver().resolve(root, in: .init(identity: testIdentity("Root")))

    #expect(resolved.identity == testIdentity("Root"))
    #expect(resolved.kind == .view("VStack"))
    #expect(resolved.children.count == 4)
    #expect(resolved.children[0].identity == testIdentity("Root", "VStack[0]"))
    #expect(resolved.children[1].identity == testIdentity("Root", "true", "VStack[1]"))
    #expect(resolved.children[2].identity == testIdentity("Root", "VStack[2]", "Group[0]"))
    #expect(resolved.children[3].identity == testIdentity("Root", "VStack[2]", "Group[2]"))
  }

  @Test("root Group resolves into a synthetic structural wrapper when multiple elements remain")
  func rootGroupResolvesToSyntheticWrapper() {
    let root = Group {
      Text("A")
      Text("B")
    }

    let resolved = Resolver().resolve(root, in: .init(identity: testIdentity("Root")))

    #expect(resolved.identity == testIdentity("Root"))
    #expect(resolved.kind == .view("Group"))
    #expect(resolved.children.count == 2)
    #expect(resolved.children[0].identity == testIdentity("Root", "Group[0]"))
    #expect(resolved.children[1].identity == testIdentity("Root", "Group[1]"))
  }

  @Test("default renderer accepts the SwiftUI-shaped surface end to end")
  func defaultRendererAcceptsSwiftUISurface() {
    let root = VStack {
      Text("Hello")
      Group {
        Text("Wide")
        Text("UI")
      }
    }

    let artifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.resolvedTree.kind == .view("VStack"))
    #expect(artifacts.placedTree.children.count == 3)
    #expect(artifacts.rasterSurface.lines == ["Hello", "Wide", " UI"])
  }

  @Test(
    "public lifecycle modifiers register on the resolved node without executing during resolution")
  func publicLifecycleModifiersRegisterWithoutExecuting() async throws {
    final class CounterBox: Sendable {
      private struct State: Sendable {
        var appearCount = 0
        var disappearCount = 0
        var taskCount = 0
      }

      private let state = LockedBox(State())

      var appearCount: Int {
        get { state.value.appearCount }
        set { state.withLock { $0.appearCount = newValue } }
      }

      var disappearCount: Int {
        get { state.value.disappearCount }
        set { state.withLock { $0.disappearCount = newValue } }
      }

      var taskCount: Int {
        get { state.value.taskCount }
        set { state.withLock { $0.taskCount = newValue } }
      }
    }

    let counters = CounterBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()

    let resolved = Resolver().resolve(
      Text("Load")
        .onAppear { counters.appearCount += 1 }
        .onDisappear { counters.disappearCount += 1 }
        .task(priority: .high) { counters.taskCount += 1 },
      in: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(resolved.identity == testIdentity("Root"))
    #expect(counters.appearCount == 0)
    #expect(counters.disappearCount == 0)
    #expect(counters.taskCount == 0)
    #expect(resolved.lifecycleMetadata.appearHandlerIDs == ["Root#appear[0]"])
    #expect(resolved.lifecycleMetadata.disappearHandlerIDs == ["Root#disappear[0]"])
    #expect(resolved.lifecycleMetadata.task == .init(id: "Root#task", priority: .high))
    #expect(lifecycleRegistry.appearHandler(for: "Root#appear[0]") != nil)
    #expect(lifecycleRegistry.disappearHandler(for: "Root#disappear[0]") != nil)

    let taskRegistration = try #require(taskRegistry.registration(for: testIdentity("Root")))
    #expect(taskRegistration.descriptor == TaskDescriptor(id: "Root#task", priority: .high))

    await MainActor.run {
      lifecycleRegistry.appearHandler(for: "Root#appear[0]")?()
      lifecycleRegistry.disappearHandler(for: "Root#disappear[0]")?()
    }
    await taskRegistration.run()

    #expect(counters.appearCount == 1)
    #expect(counters.disappearCount == 1)
    #expect(counters.taskCount == 1)
  }

  @Test(
    "onChange(of:initial:_:) defers execution until commit and tracks old and new values")
  func onChangeDefersExecutionUntilCommitAndTracksOldAndNewValues() async {
    final class ChangeBox: Sendable {
      private struct State: Sendable {
        var events: [String] = []
      }

      private let state = LockedBox(State())

      var events: [String] {
        state.value.events
      }

      func record(oldValue: Int, newValue: Int) {
        state.withLock { state in
          state.events.append("\(oldValue)->\(newValue)")
        }
      }
    }

    let box = ChangeBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let renderer = DefaultRenderer()

    func makeView(_ value: Int) -> some View {
      Text("Value \(value)")
        .onChange(of: value, initial: true) { oldValue, newValue in
          box.record(oldValue: oldValue, newValue: newValue)
        }
    }

    let initialArtifacts = renderer.render(
      makeView(1),
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(box.events.isEmpty)
    #expect(
      initialArtifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root"),
          operation: .change(handlerIDs: ["Root#change[0]"])
        )
      ]
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "Root#change[0]")?()
    }

    #expect(box.events == ["1->1"])

    let updatedArtifacts = renderer.render(
      makeView(2),
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      updatedArtifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root"),
          operation: .change(handlerIDs: ["Root#change[0]"])
        )
      ]
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "Root#change[0]")?()
    }

    #expect(box.events == ["1->1", "1->2"])

    let unchangedArtifacts = renderer.render(
      makeView(2),
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(unchangedArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test(
    "onChange attached to a stateful view reserves modifier storage after body state slots"
  )
  func onChangeOnStatefulViewDoesNotCollideWithBodyStateSlots() async {
    final class ChangeBox: Sendable {
      private struct State: Sendable {
        var events: [String] = []
      }

      private let state = LockedBox(State())

      var events: [String] {
        state.value.events
      }

      func record(oldValue: Int, newValue: Int) {
        state.withLock { state in
          state.events.append("\(oldValue)->\(newValue)")
        }
      }
    }

    struct StatefulOnChangeFixture: View {
      let box: ChangeBox

      @State private var color: Color = .red
      @State private var count: Int = 1
      @State private var step: Int = 2

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Color")
            .foregroundStyle(color)
          Text("Count \(count)")
          Text("Step \(step)")
        }
        .onChange(of: count, initial: true) { oldValue, newValue in
          box.record(oldValue: oldValue, newValue: newValue)
        }
      }
    }

    let box = ChangeBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let renderer = DefaultRenderer()

    let artifacts = renderer.render(
      StatefulOnChangeFixture(box: box),
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      artifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root"),
          operation: .change(handlerIDs: ["Root#change[0]"])
        )
      ]
    )

    await MainActor.run {
      lifecycleRegistry.changeHandler(for: "Root#change[0]")?()
    }

    #expect(box.events == ["1->1"])
  }

  @Test(
    "conditional lifecycle ownership follows the resolved branch identity instead of inventing a wrapper"
  )
  func conditionalLifecycleOwnershipFollowsResolvedBranchIdentity() {
    func makeRoot(_ isVisible: Bool) -> some View {
      Group {
        if isVisible {
          Text("Shown")
        } else {
          Text("Hidden")
        }
      }
      .onAppear {}
      .task(id: isVisible ? "shown" : "hidden") {}
    }

    let shown = Resolver().resolve(makeRoot(true), in: .init(identity: testIdentity("Root")))
    let hidden = Resolver().resolve(makeRoot(false), in: .init(identity: testIdentity("Root")))

    #expect(shown.identity == testIdentity("Root", "true", "Group[0]"))
    #expect(hidden.identity == testIdentity("Root", "false", "Group[0]"))
    #expect(shown.lifecycleMetadata.appearHandlerIDs == ["Root/true/Group[0]#appear[0]"])
    #expect(hidden.lifecycleMetadata.appearHandlerIDs == ["Root/false/Group[0]#appear[0]"])
    #expect(
      shown.lifecycleMetadata.task
        == .init(id: "Root/true/Group[0]#task[\"shown\"]", priority: .medium))
    #expect(
      hidden.lifecycleMetadata.task
        == .init(id: "Root/false/Group[0]#task[\"hidden\"]", priority: .medium))
  }

  @Test(
    "public lifecycle and task modifiers drive insertion removal and task replacement commit deltas"
  )
  func publicLifecycleAndTaskModifiersDriveCommitDeltas() {
    func makeConditionalRoot(showRow: Bool, taskID: String = "load") -> some View {
      VStack {
        if showRow {
          Text("Row")
            .onAppear {}
            .onDisappear {}
            .task(id: taskID) {}
        }
      }
    }

    let renderer = DefaultRenderer()

    _ = renderer.render(
      makeConditionalRoot(showRow: false),
      context: .init(identity: testIdentity("Root"))
    )
    let shownArtifacts = renderer.render(
      makeConditionalRoot(showRow: true),
      context: .init(identity: testIdentity("Root"))
    )
    let updatedTaskArtifacts = renderer.render(
      makeConditionalRoot(showRow: true, taskID: "refresh"),
      context: .init(identity: testIdentity("Root"))
    )
    let removedArtifacts = renderer.render(
      makeConditionalRoot(showRow: false),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(
      shownArtifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .appear(handlerIDs: ["Root/true/VStack[0]#appear[0]"])
        ),
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .taskStart(.init(id: "Root/true/VStack[0]#task[\"load\"]", priority: .medium))
        ),
      ]
    )
    #expect(
      updatedTaskArtifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .taskCancel(
            .init(id: "Root/true/VStack[0]#task[\"load\"]", priority: .medium))
        ),
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .taskStart(
            .init(id: "Root/true/VStack[0]#task[\"refresh\"]", priority: .medium))
        ),
      ]
    )
    #expect(
      removedArtifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .taskCancel(
            .init(id: "Root/true/VStack[0]#task[\"refresh\"]", priority: .medium))
        ),
        .init(
          identity: testIdentity("Root", "true", "VStack[0]"),
          operation: .disappear(handlerIDs: ["Root/true/VStack[0]#disappear[0]"])
        ),
      ]
    )
  }

  @Test("focus changes do not emit lifecycle deltas for stable public lifecycle owners")
  func focusChangesDoNotEmitLifecycleDeltas() {
    var unfocusedEnvironment = EnvironmentValues()
    unfocusedEnvironment.focusedIdentity = nil

    var focusedEnvironment = EnvironmentValues()
    focusedEnvironment.focusedIdentity = testIdentity("Focusable")

    let view = Text("Focus")
      .focusable()
      .id(testIdentity("Focusable"))
      .onAppear {}
      .onDisappear {}
      .task(id: "stable") {}

    let renderer = DefaultRenderer()

    _ = renderer.render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: unfocusedEnvironment
      )
    )
    let focusedArtifacts = renderer.render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: focusedEnvironment
      )
    )

    #expect(focusedArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("scroll position changes do not emit lifecycle deltas for off-screen stable identities")
  func scrollPositionChangesDoNotEmitLifecycleDeltas() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
          .onAppear {}
          .onDisappear {}
          .task(id: "row-2") {}
      }
    }
    .frame(width: 5, height: 2, alignment: .topLeading)

    let renderer = DefaultRenderer()

    _ = renderer.render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    box.position.scrollBy(y: 1)

    let scrolledArtifacts = renderer.render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(scrolledArtifacts.rasterSurface.lines.prefix(2) == ["Row 1", "Row 2"])
    #expect(scrolledArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("custom View types can author through body like SwiftUI")
  func customBodyBasedViewsResolveThroughBody() {
    let resolved = Resolver().resolve(
      BodyBasedCard(
        title: "Status",
        value: "Ready"
      ),
      in: .init(identity: testIdentity("Root"))
    )

    #expect(resolved.descendant(withText: "Status") != nil)
    #expect(resolved.descendant(withText: "Ready") != nil)
  }

  @Test("body-based custom views compose with external modifiers and preserve semantics")
  func bodyBasedViewsComposeWithModifiers() {
    let artifacts = DefaultRenderer().render(
      BodyBasedCard(
        title: "Queue",
        value: "Build"
      )
      .id(testIdentity("QueueCard"))
      .semanticMetadata(.init(scrollRole: .scrollView))
      .foregroundStyle(.tint),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.resolvedTree.identity == testIdentity("QueueCard"))
    #expect(artifacts.resolvedTree.semanticMetadata.scrollRole == .scrollView)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Queue"))
  }

  @Test("@State persists on the same view instance when local button actions fire")
  func statePersistsAcrossRepeatedResolutionOfTheSameViewInstance() throws {
    let localActionRegistry = LocalActionRegistry()
    let view = BodyBasedStatefulCounter()

    let initialArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        localActionRegistry: localActionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(initialArtifacts.rasterSurface.lines.contains("Count 0"))

    let actionIdentity = try #require(
      initialArtifacts.semanticSnapshot.focusRegions.first?.identity)
    #expect(localActionRegistry.dispatch(identity: actionIdentity))

    let updatedArtifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(updatedArtifacts.rasterSurface.lines.contains("Count 1"))
  }

  @Test("@State projected bindings drive controls on the same view instance")
  func stateProjectedBindingsDriveControls() throws {
    let localKeyHandlerRegistry = LocalKeyHandlerRegistry()
    let view = BodyBasedStatefulField()

    let initialArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        localKeyHandlerRegistry: localKeyHandlerRegistry,
        applyEnvironmentValues: true
      )
    )

    let fieldIdentity = try #require(initialArtifacts.semanticSnapshot.focusRegions.first?.identity)
    #expect(localKeyHandlerRegistry.dispatch(identity: fieldIdentity, event: .character("H")))
    #expect(localKeyHandlerRegistry.dispatch(identity: fieldIdentity, event: .character("i")))

    let updatedArtifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(updatedArtifacts.rasterSurface.lines.contains(where: { $0.contains("Name: Hi") }))
  }

  @Test(
    "@State reads in body use graph-owned slots when a view is re-rendered through bindings")
  func stateReadsInBodyUseGraphOwnedSlots() throws {
    let localActionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let view = BodyBasedStatefulCounter()
    let context = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: localActionRegistry,
      applyEnvironmentValues: true
    )

    let initialArtifacts = renderer.render(
      view,
      context: context
    )

    #expect(initialArtifacts.rasterSurface.lines.contains("Count 0"))

    let actionIdentity = try #require(
      initialArtifacts.semanticSnapshot.focusRegions.first?.identity)
    #expect(localActionRegistry.dispatch(identity: actionIdentity))

    let updatedArtifacts = renderer.render(
      view,
      context: context
    )

    #expect(updatedArtifacts.rasterSurface.lines.contains("Count 1"))
  }

  @Test(
    "@State button actions stay bound to their original runtime scope when the same view instance is rebound"
  )
  func stateButtonActionsStayBoundToTheirOriginalRuntimeScope() throws {
    let view = BodyBasedStatefulCounter()
    let firstActionRegistry = LocalActionRegistry()
    let secondActionRegistry = LocalActionRegistry()
    let firstRenderer = DefaultRenderer()
    let secondRenderer = DefaultRenderer()

    let firstContext = ResolveContext(
      identity: testIdentity("RootA"),
      localActionRegistry: firstActionRegistry,
      applyEnvironmentValues: true
    )
    let firstArtifacts = firstRenderer.render(
      view,
      context: firstContext
    )
    let firstActionIdentity = try #require(
      firstArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    let secondContext = ResolveContext(
      identity: testIdentity("RootB"),
      localActionRegistry: secondActionRegistry,
      applyEnvironmentValues: true
    )
    let secondArtifacts = secondRenderer.render(
      view,
      context: secondContext
    )
    let secondActionIdentity = try #require(
      secondArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    #expect(firstActionIdentity != secondActionIdentity)
    #expect(firstActionRegistry.dispatch(identity: firstActionIdentity))

    let updatedFirstArtifacts = firstRenderer.render(
      view,
      context: firstContext
    )
    let updatedSecondArtifacts = secondRenderer.render(
      view,
      context: secondContext
    )

    #expect(updatedFirstArtifacts.rasterSurface.lines.contains("Count 1"))
    #expect(updatedSecondArtifacts.rasterSurface.lines.contains("Count 0"))
  }

  @Test("public metadata modifiers update resolved identity, layout, draw, and semantic state")
  func publicMetadataModifiersUpdateResolvedState() {
    let resolved = Resolver().resolve(
      Text("Go")
        .foregroundStyle(.tint)
        .id(testIdentity("Explicit", "Button"))
        .layoutPriority(2)
        .focusable(),
      in: .init(identity: testIdentity("Root"))
    )

    #expect(resolved.identity == testIdentity("Explicit", "Button"))
    #expect(resolved.layoutMetadata.layoutPriority == 2)
    #expect(resolved.drawMetadata.foregroundStyle == .semantic(.tint))
    #expect(resolved.semanticMetadata.isFocusable == true)
    #expect(resolved.semanticMetadata.participatesInPointerHitTesting)
  }

  @Test("focusable false and explicit semantic opt-out both suppress built-in top-level focus")
  func explicitFocusOptOutSuppressesAutomaticControlFocus() {
    let modifierOptOut = DefaultRenderer().render(
      Button("Save") {}
        .focusable(false),
      context: .init(identity: testIdentity("ModifierOptOut"))
    )
    let explicitlyExcluded = DefaultRenderer().render(
      Button("Save") {}
        .semanticMetadata(.init(isFocusable: false)),
      context: .init(identity: testIdentity("SemanticOptOut"))
    )
    let explicitlyIncludedScrollView = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        Text("Row 0")
        Text("Row 1")
      }
      .id(testIdentity("FocusableScroll"))
      .focusable(),
      context: .init(identity: testIdentity("FocusableScrollRoot"))
    )

    #expect(modifierOptOut.semanticSnapshot.focusRegions.isEmpty)
    #expect(explicitlyExcluded.semanticSnapshot.focusRegions.isEmpty)
    #expect(
      explicitlyIncludedScrollView.semanticSnapshot.focusRegions.map(\.identity)
        == [testIdentity("FocusableScroll")]
    )
  }

  @Test("automatic controls and explicit focusable surfaces share the same focus order")
  func automaticControlsAndExplicitFocusableSurfacesShareFocusOrder() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Button("Action") {}
          .id(testIdentity("ActionButton"))
        ScrollView(.vertical, showsIndicators: false) {
          Text("Scrollable")
        }
        .id(testIdentity("FocusableScroll"))
        .focusable()
        Button("Skip") {}
          .id(testIdentity("SkippedButton"))
          .focusable(false)
      },
      context: .init(identity: testIdentity("FocusOrderRoot"))
    )

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity)
        == [testIdentity("ActionButton"), testIdentity("FocusableScroll")]
    )
  }

  @Test(
    "draw metadata merge preserves inherited opacity unless a later wrapper resets it explicitly")
  func drawMetadataOpacityMergeSupportsExplicitReset() {
    let inherited = Resolver().resolve(
      Text("Dim")
        .drawMetadata(.init(opacity: 0.4))
        .drawMetadata(.init()),
      in: .init(identity: testIdentity("InheritedOpacity"))
    )
    let reset = Resolver().resolve(
      Text("Reset")
        .drawMetadata(.init(opacity: 0.4))
        .drawMetadata(.init(opacity: 1)),
      in: .init(identity: testIdentity("ResetOpacity"))
    )

    #expect(inherited.drawMetadata.opacity == 0.4)
    #expect(inherited.drawMetadata.explicitOpacity == 0.4)
    #expect(reset.drawMetadata.opacity == 1)
    #expect(reset.drawMetadata.explicitOpacity == 1)
  }

  @Test("draw metadata keeps list-specific fields in a dedicated list-style payload")
  func drawMetadataUsesDedicatedListStylePayload() throws {
    let resolved = Resolver().resolve(
      Text("Row")
        .drawMetadata(
          .init(
            listStyle: .init(
              rowBackgroundStyle: AnyShapeStyle(Color.blue),
              rowSeparatorBottomVisibility: .hidden
            )
          )
        )
        .drawMetadata(
          .init(
            listStyle: .init(
              rowForegroundStyle: AnyShapeStyle(Color.yellow),
              sectionSeparatorTopVisibility: .hidden
            )
          )
        ),
      in: .init(identity: testIdentity("ListStylePayload"))
    )

    let listStyle = try #require(resolved.drawMetadata.listStyle)

    #expect(listStyle.rowForegroundStyle == AnyShapeStyle(Color.yellow))
    #expect(listStyle.rowBackgroundStyle == AnyShapeStyle(Color.blue))
    #expect(listStyle.rowSeparatorBottomVisibility == .hidden)
    #expect(listStyle.sectionSeparatorTopVisibility == .hidden)

    // Compatibility accessors still read through the dedicated list-style payload.
    #expect(resolved.drawMetadata.listRowForegroundStyle == AnyShapeStyle(Color.yellow))
    #expect(resolved.drawMetadata.listRowBackgroundStyle == AnyShapeStyle(Color.blue))
  }

  @Test("environment values can be injected, overridden, and read structurally")
  func environmentValuesCanBeReadAndOverridden() {
    var rootEnvironmentValues = EnvironmentValues()
    rootEnvironmentValues.sampleTheme = .init(
      accent: "root-accent",
      emphasis: "root-emphasis"
    )

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        EnvironmentReader(\.sampleTheme) { theme in
          Text("Root: \(theme.accent)")
        }
        Group {
          EnvironmentReader(\.sampleTheme) { theme in
            Text("Inner: \(theme.accent)")
          }
        }
        .environment(
          \.sampleTheme,
          .init(accent: "nested-accent", emphasis: "nested-emphasis")
        )
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: rootEnvironmentValues
      )
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "Root: root-accent",
        "Inner: nested-accent",
      ])
    #expect(
      artifacts.resolvedTree.environmentSnapshot.values[String(reflecting: SampleThemeKey.self)]
        != nil)
  }

  @Test("transformEnvironment mutates inherited values for descendants")
  func transformEnvironmentMutatesInheritedValues() {
    let resolved = Resolver().resolve(
      EnvironmentReader(\.surfaceName) { name in
        Text("Surface: \(name)")
      }
      .transformEnvironment(\.surfaceName) { name in
        name += "-styled"
      }
      .environment(\.surfaceName, "terminal"),
      in: .init(identity: testIdentity("Root"))
    )

    #expect(resolved.drawPayload == .text("Surface: terminal-styled"))
    #expect(
      resolved.environmentSnapshot.values[String(reflecting: SurfaceNameKey.self)]
        == "\"terminal-styled\""
    )
  }

  @Test("padding and frame participate in measurement and placement")
  func paddingAndFrameParticipateInLayout() {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(.init(all: 1))
        .frame(width: 6, height: 5, alignment: .bottomTrailing),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 6, height: 5))
    #expect(artifacts.placedTree.kind == .view("Frame"))
    #expect(artifacts.placedTree.children.count == 1)
    #expect(artifacts.placedTree.children[0].kind == .view("Padding"))
    #expect(artifacts.placedTree.children[0].bounds.origin == .init(x: 2, y: 2))
    #expect(artifacts.placedTree.children[0].bounds.size == .init(width: 4, height: 3))
  }

  @Test("background and overlay are size-neutral wrappers on the new surface")
  func backgroundAndOverlayAreSizeNeutral() {
    let backgroundArtifacts = DefaultRenderer().render(
      Text("Hi").background {
        Text("WIDE")
      },
      context: .init(identity: testIdentity("Background"))
    )
    let overlayArtifacts = DefaultRenderer().render(
      Text("Hi").overlay {
        Text("X")
      },
      context: .init(identity: testIdentity("Overlay"))
    )

    #expect(backgroundArtifacts.measuredTree.measuredSize == .init(width: 2, height: 1))
    #expect(overlayArtifacts.measuredTree.measuredSize == .init(width: 2, height: 1))
    #expect(backgroundArtifacts.rasterSurface.lines == ["Hi"])
    #expect(overlayArtifacts.rasterSurface.lines == ["Xi"])
  }

  @Test("text preserves filled underlay backgrounds when composited on top")
  @MainActor
  func textPreservesFilledUnderlayBackground() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = .init(
      foregroundColor: .yellow,
      backgroundColor: hexColor("#112233"),
      tintColor: .cyan,
      source: .override
    )

    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .frame(width: 4, height: 1, alignment: .leading)
        .background(.background),
      context: .init(
        identity: testIdentity("BackgroundFill"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines == ["Hi  "])
    #expect(
      artifacts.rasterSurface.cells[0][0].style
        == .init(
          foregroundColor: .yellow,
          backgroundColor: hexColor("#112233")
        ))
    #expect(
      artifacts.rasterSurface.cells[0][1].style
        == .init(
          foregroundColor: .yellow,
          backgroundColor: hexColor("#112233")
        ))
  }

  @Test("stroked borders keep underlay backgrounds out of the border ring")
  @MainActor
  func strokedBordersKeepUnderlayBackgroundOutOfBorderRing() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = .init(
      foregroundColor: .yellow,
      backgroundColor: hexColor("#112233"),
      tintColor: .cyan,
      source: .override
    )

    let artifacts = DefaultRenderer().render(
      EmptyView()
        .frame(width: 4, height: 3, alignment: .topLeading)
        .background(.background)
        .overlay {
          Rectangle().strokeBorder(Color.red)
        },
      context: .init(
        identity: testIdentity("BorderFill"),
        environmentValues: environmentValues
      )
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "┌──┐",
        "│  │",
        "└──┘",
      ])
    #expect(
      artifacts.rasterSurface.cells[0][0].style
        == ResolvedTextStyle(
          foregroundColor: .red
        ))
    #expect(
      artifacts.rasterSurface.cells[1][1].style
        == ResolvedTextStyle(
          backgroundColor: hexColor("#112233")
        ))
  }

  @Test("rounded border overlays clip background fills to the rounded interior")
  @MainActor
  func roundedBorderOverlayClipsBackgroundFillsToRoundedInterior() {
    let artifacts = DefaultRenderer().render(
      EmptyView()
        .frame(width: 5, height: 3, alignment: .topLeading)
        .background(.warning)
        .overlay {
          RoundedRectangle(cornerRadius: 1).strokeBorder(.danger)
        },
      context: .init(identity: testIdentity("RoundedBorderBackgroundMask"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "╭───╮",
        "│   │",
        "╰───╯",
      ])
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[1][2].style?.backgroundColor != nil)
  }

  @Test("stroked shapes keep border cells free of interior fill by default")
  @MainActor
  func strokedShapesKeepBorderCellsFreeOfInteriorFill() {
    let artifacts = DefaultRenderer().render(
      RoundedRectangle(cornerRadius: 1)
        .inset(by: 1).fill(.warning)
        .overlay {
          RoundedRectangle(cornerRadius: 1).strokeBorder(.danger)
        }
        .frame(width: 5, height: 3, alignment: .topLeading),
      context: .init(identity: testIdentity("InteriorOnlyFill"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "╭───╮",
        "│   │",
        "╰───╯",
      ])
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[1][2].style?.backgroundColor != nil)
  }

  @Test("rounded inset fills preserve rounded corner cells on taller containers")
  @MainActor
  func roundedInsetFillsPreserveRoundedCornerCells() {
    let artifacts = DefaultRenderer().render(
      RoundedRectangle(cornerRadius: 1)
        .inset(by: 1).fill(.warning)
        .overlay {
          RoundedRectangle(cornerRadius: 1).strokeBorder(.danger)
        }
        .frame(width: 7, height: 5, alignment: .topLeading),
      context: .init(identity: testIdentity("TallRoundedInteriorFill"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "╭─────╮",
        "│     │",
        "│     │",
        "│     │",
        "╰─────╯",
      ])
    #expect(artifacts.rasterSurface.cells[1][1].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[1][5].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[3][1].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[3][5].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[2][3].style?.backgroundColor != nil)
  }

  @Test("explicit internal border background styles only the border ring")
  @MainActor
  func explicitBorderBackgroundOnlyStylesBorderRing() {
    let artifacts = DefaultRenderer().render(
      RoundedRectangle(cornerRadius: 1)
        .chromeStrokeBorder(.danger, backgroundStyle: AnyShapeStyle(.warning))
        .frame(width: 5, height: 3, alignment: .topLeading),
      context: .init(identity: testIdentity("BorderBackground"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "╭───╮",
        "│   │",
        "╰───╯",
      ])
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor != nil)
    #expect(artifacts.rasterSurface.cells[1][2].style == nil)
  }

  @Test("public strokeBorder background styles the full border ring")
  @MainActor
  func publicStrokeBorderBackgroundStylesBorderRing() {
    let artifacts = DefaultRenderer().render(
      RoundedRectangle(cornerRadius: 1)
        .strokeBorder(.danger, background: .warning)
        .frame(width: 5, height: 3, alignment: .topLeading),
      context: .init(identity: testIdentity("PublicBorderBackground"))
    )

    #expect(artifacts.rasterSurface.lines == ["╭───╮", "│   │", "╰───╯"])
    #expect(artifacts.rasterSurface.cells[0][2].style?.backgroundColor == Color.yellow)
    #expect(artifacts.rasterSurface.cells[1][0].style?.backgroundColor == Color.yellow)
    #expect(artifacts.rasterSurface.cells[1][2].style == nil)
  }

  @Test("border background styles can target each edge independently")
  @MainActor
  func borderBackgroundStylesCanTargetEdgesIndependently() {
    let artifacts = DefaultRenderer().render(
      Rectangle()
        .strokeBorder(
          .separator,
          background: BorderBackgroundStyle(
            top: Color.yellow,
            right: Color.blue,
            bottom: Color.green,
            left: Color.red
          )
        )
        .frame(width: 5, height: 4, alignment: .topLeading),
      context: .init(identity: testIdentity("DirectionalBorderBackground"))
    )

    #expect(artifacts.rasterSurface.lines == ["┌───┐", "│   │", "│   │", "└───┘"])
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor == Color.yellow)
    #expect(artifacts.rasterSurface.cells[1][0].style?.backgroundColor == Color.red)
    #expect(artifacts.rasterSurface.cells[1][4].style?.backgroundColor == Color.blue)
    #expect(artifacts.rasterSurface.cells[3][2].style?.backgroundColor == Color.green)
    #expect(artifacts.rasterSurface.cells[1][2].style == nil)
  }

  @Test("stroke borders sample the surrounding background instead of leaking the fill")
  @MainActor
  func strokeBordersUseSurroundingBackgroundOutsideTheFill() {
    let artifacts = DefaultRenderer().render(
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.blue)
        .frame(width: 4, height: 3, alignment: .topLeading)
        .overlay {
          RoundedRectangle(cornerRadius: 1)
            .strokeBorder(Color.white, style: .rounded)
        }
        .padding(1)
        .background {
          Rectangle().fill(Color.green)
        },
      context: .init(identity: testIdentity("BorderBackgroundSampling"))
    )

    #expect(artifacts.rasterSurface.lines == ["      ", " ╭──╮ ", " │  │ ", " ╰──╯ ", "      "])
    #expect(artifacts.rasterSurface.cells[1][2].style?.backgroundColor == Color.green)
    #expect(artifacts.rasterSurface.cells[2][1].style?.backgroundColor == Color.green)
    #expect(artifacts.rasterSurface.cells[2][2].style?.backgroundColor == Color.blue)
  }

  @Test("terminal appearance derives semantic foreground and background roles")
  @MainActor
  func terminalAppearanceDerivesSemanticRoles() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = .init(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )

    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .frame(width: 4, height: 1, alignment: .leading)
        .background(.background),
      context: .init(
        identity: testIdentity("AppearanceRoles"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines == ["Hi  "])
    #expect(
      artifacts.rasterSurface.cells[0][0].style
        == .init(
          foregroundColor: .black,
          backgroundColor: .white
        ))
    #expect(
      artifacts.rasterSurface.cells[0][1].style
        == .init(
          foregroundColor: .black,
          backgroundColor: .white
        ))
  }

  @Test("explicit foregroundStyle and tint override appearance-derived defaults")
  func explicitStyleAndTintOverrideAppearanceDefaults() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = .init(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Tint").foregroundStyle(.tint)
        Text("Color").foregroundStyle(Color.red)
        Text("Override").foregroundStyle(.tint).tint(Color.yellow)
      },
      context: .init(
        identity: testIdentity("AppearanceOverrides"),
        environmentValues: environmentValues
      )
    )

    #expect(
      artifacts.rasterSurface.cells[0][0].style?.foregroundColor?.hexString()
        == Color.blue.hexString()
    )
    #expect(
      artifacts.rasterSurface.cells[1][0].style?.foregroundColor?.hexString()
        == Color.red.hexString()
    )
    #expect(
      artifacts.rasterSurface.cells[2][0].style?.foregroundColor?.hexString()
        == Color.yellow.hexString()
    )
  }

  @Test("node draw metadata foregroundStyle wins over inherited environment foregroundStyle")
  func nodeForegroundStyleOverridesEnvironmentForegroundStyle() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Node").foregroundStyle(Color.red)
        Text("Inherited")
      }
      .foregroundStyle(Color.blue),
      context: .init(identity: testIdentity("ForegroundPrecedence"))
    )

    #expect(artifacts.rasterSurface.cells[0][0].style?.foregroundColor == Color.red)
    #expect(artifacts.rasterSurface.cells[1][0].style?.foregroundColor == Color.blue)
  }

  @Test("resolveStyleColorResult resolves semantic colors and surfaces empty-gradient diagnostics")
  func colorResolutionDiagnosticsAreExplicit() {
    let theme = Theme(
      foreground: .hex("#102030")
    )
    let emptyGradient = LinearGradient(
      gradient: .init(stops: []),
      startPoint: .leading,
      endPoint: .trailing
    )

    #expect(
      resolveStyleColorResult(
        style: .semantic(.foreground),
        theme: theme
      ) == .success(.hex("#102030"))
    )
    #expect(
      resolveStyleColorResult(
        style: .linearGradient(emptyGradient),
        theme: .default
      ) == .failure(.emptyGradient)
    )
  }

  @Test("terminal chrome shape styles resolve through synthesized appearances")
  func terminalChromeShapeStylesResolveToConcreteColors() {
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    let theme = appearance.synthesizedTheme()

    let accent = resolveStyleColor(
      style: AnyShapeStyle(.terminalAccent(.warning)),
      theme: theme
    )
    let surface = resolveStyleColor(
      style: AnyShapeStyle(.terminalSurface(.warning)),
      theme: theme
    )
    let row = resolveStyleColor(
      style: AnyShapeStyle(.terminalRow(.warning, isSelected: true)),
      theme: theme
    )

    #expect(accent != nil)
    #expect(surface != nil)
    #expect(row != nil)
    #expect(accent != surface)
  }

  @Test("explicit theme overrides appearance-derived semantic and chrome colors")
  func explicitThemeOverridesAppearanceDerivedSemanticAndChromeColors() {
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    let theme = Theme(
      foreground: .hex("#111827"),
      background: .hex("#F8FAFC"),
      tint: .hex("#2563EB"),
      separator: .hex("#CBD5E1"),
      selection: .hex("#DBEAFE"),
      placeholder: .hex("#94A3B8"),
      link: .hex("#2563EB"),
      fill: .hex("#F1F5F9"),
      windowBackground: .hex("#E2E8F0"),
      success: .hex("#16A34A"),
      warning: .hex("#D97706"),
      danger: .hex("#DC2626"),
      info: .hex("#0284C7"),
      muted: .hex("#64748B")
    )
    let snapshot = StyleEnvironmentSnapshot(
      appearance: appearance,
      theme: theme
    )

    #expect(
      resolveStyleColor(
        style: .semantic(.warning),
        theme: snapshot.theme
      ) == theme.warning
    )
    #expect(
      resolveStyleColor(
        style: AnyShapeStyle(.terminalAccent(.warning)),
        theme: snapshot.theme,
        appearance: snapshot.appearance
      ) == theme.warning
    )
    #expect(
      resolveStyleColor(
        style: AnyShapeStyle(.terminalAccent(.success)),
        theme: snapshot.theme,
        appearance: snapshot.appearance
      ) == theme.success
    )
  }

  @Test(
    "disabled writes isEnabled into environment and outer disabled overrides inner enabled requests"
  )
  func disabledWritesEnvironmentAndAncestorsOverride() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        EnvironmentReader(\.isEnabled) { isEnabled in
          Text("Outer \(isEnabled)")
        }
        EnvironmentReader(\.isEnabled) { isEnabled in
          Text("Inner \(isEnabled)")
        }
        .disabled(false)
      }
      .disabled(true),
      context: .init(identity: testIdentity("DisabledHierarchy"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "Outer false",
        "Inner false",
      ])
  }

  @Test("disabled nodes are excluded from focus, action, and scroll semantics")
  func disabledNodesAreExcludedFromInteractiveSemantics() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Enabled")
          .id(testIdentity("enabled"))
          .focusable()
        Text("Disabled")
          .id(testIdentity("disabled"))
          .disabled(true)
          .focusable()
        Text("Scroll")
          .id(testIdentity("scroll"))
          .disabled(true)
          .semanticMetadata(.init(scrollRole: .scrollView, presentationRole: .scrollView))
      },
      context: .init(identity: testIdentity("Semantics"))
    )

    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("enabled")])
    #expect(
      artifacts.semanticSnapshot.interactionRegions.map(\.identity) == [testIdentity("enabled")])
    #expect(artifacts.semanticSnapshot.scrollRoutes.isEmpty)
    #expect(artifacts.semanticSnapshot.selectionRoutes.isEmpty)
  }

  @Test("style environment snapshot derives control chrome for idle, focused, and disabled states")
  func styleEnvironmentSnapshotDerivesControlChromeStates() {
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    let snapshot = StyleEnvironmentSnapshot(appearance: appearance)
    let semanticTheme = snapshot.theme

    let idle = snapshot.controlChrome(
      isEnabled: true,
      isFocused: false
    )
    let focused = snapshot.controlChrome(
      isEnabled: true,
      isFocused: true
    )
    let disabled = snapshot.controlChrome(
      isEnabled: false,
      isFocused: false
    )

    #expect(idle.foregroundStyle == semanticTheme.style(for: .foreground))
    #expect(
      resolveStyleColor(style: idle.backgroundStyle, theme: semanticTheme, appearance: appearance)
        != nil)
    #expect(
      resolveStyleColor(style: idle.borderStyle, theme: semanticTheme, appearance: appearance)
        != nil)
    #expect(idle.opacity == 1)

    #expect(
      resolveStyleColor(
        style: focused.backgroundStyle, theme: semanticTheme, appearance: appearance) != nil)
    #expect(
      resolveStyleColor(style: focused.borderStyle, theme: semanticTheme, appearance: appearance)
        != nil)
    #expect(idle.borderStyle != focused.borderStyle)
    #expect(focused.opacity == 1)

    #expect(disabled.foregroundStyle == semanticTheme.style(for: .placeholder))
    #expect(
      resolveStyleColor(
        style: disabled.backgroundStyle, theme: semanticTheme, appearance: appearance) != nil)
    #expect(
      resolveStyleColor(style: disabled.borderStyle, theme: semanticTheme, appearance: appearance)
        != nil)
    #expect(disabled.opacity == 0.6)
  }

  @Test("Label composes icon and title with SwiftUI-shaped builder semantics")
  func labelRendersIconAndTitle() {
    let artifacts = DefaultRenderer().render(
      Label("Network") {
        Text("◎")
      },
      context: .init(identity: testIdentity("Label"))
    )

    #expect(artifacts.rasterSurface.lines == ["◎ Network"])
  }

  @Test("LabeledContent aligns a muted label against trailing value content")
  func labeledContentRendersLabelAndValue() {
    let artifacts = DefaultRenderer().render(
      LabeledContent("Mode", value: "Accent")
        .frame(width: 14, height: 1, alignment: .leading),
      context: .init(identity: testIdentity("LabeledContent"))
    )

    #expect(artifacts.rasterSurface.lines == ["Mode    Accent"])
  }

  @Test("Toggle registers a local binding action and flips its bound value through the dispatcher")
  func toggleDispatchesLocalBindingAction() {
    final class ToggleBox {
      var isOn = false
    }

    let box = ToggleBox()
    let registry = LocalActionRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("AccentToggle")

    let artifacts = DefaultRenderer().render(
      Toggle(
        "Accent Preview",
        isOn: Binding(
          get: { box.isOn },
          set: { box.isOn = $0 }
        )
      )
      .id(testIdentity("AccentToggle")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let dispatched = registry.dispatch(identity: testIdentity("AccentToggle"))

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("AccentToggle")])
    #expect(dispatched)
    #expect(box.isOn)
  }

  @Test("Stepper uses local action and arrow-key handling while clamping to its bounds")
  func stepperDispatchesAndClamps() {
    final class ValueBox {
      var value = 0
    }

    let box = ValueBox()
    let actionRegistry = LocalActionRegistry()
    let keyRegistry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("CountStepper")

    let artifacts = DefaultRenderer().render(
      Stepper(
        "Count",
        value: Binding(
          get: { box.value },
          set: { box.value = $0 }
        ), in: 0...2
      )
      .id(testIdentity("CountStepper")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    let dispatched = actionRegistry.dispatch(identity: testIdentity("CountStepper"))

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("CountStepper")])
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Count"))
    #expect(dispatched)
    #expect(box.value == 1)
    #expect(keyRegistry.dispatch(identity: testIdentity("CountStepper"), event: .arrowRight))
    #expect(box.value == 2)
    #expect(!keyRegistry.dispatch(identity: testIdentity("CountStepper"), event: .arrowRight))
    #expect(keyRegistry.dispatch(identity: testIdentity("CountStepper"), event: .arrowLeft))
    #expect(box.value == 1)
  }

  @Test("Slider adjusts through left-right keys and renders a track plus value")
  func sliderHandlesArrowKeysAndRendersTrack() {
    final class ValueBox {
      var value = 1
    }

    let box = ValueBox()
    let keyRegistry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("ValueSlider")

    let artifacts = DefaultRenderer().render(
      Slider(
        "Value",
        value: Binding(
          get: { box.value },
          set: { box.value = $0 }
        ), in: 0...4
      )
      .id(testIdentity("ValueSlider")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("ValueSlider")])
    #expect(surface.contains("Value"))
    #expect(surface.contains("●"))
    #expect(keyRegistry.dispatch(identity: testIdentity("ValueSlider"), event: .arrowRight))
    #expect(box.value == 2)
    #expect(keyRegistry.dispatch(identity: testIdentity("ValueSlider"), event: .arrowLeft))
    #expect(box.value == 1)
  }

  @Test("Double Stepper and Slider support clean fractional values")
  func doubleAdjustableControlsRenderCleanFractionalValues() {
    final class StepperBox {
      var value = 0.2
    }

    final class SliderBox {
      var value = 0.45
    }

    let stepperBox = StepperBox()
    let sliderBox = SliderBox()
    let actionRegistry = LocalActionRegistry()
    let keyRegistry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("DoubleSlider")

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Stepper(
          "Amount",
          value: Binding(
            get: { stepperBox.value },
            set: { stepperBox.value = $0 }
          ),
          in: 0.0...1.0,
          step: 0.1
        )
        .id(testIdentity("DoubleStepper"))

        Slider(
          "Ratio",
          value: Binding(
            get: { sliderBox.value },
            set: { sliderBox.value = $0 }
          ),
          in: 0.0...1.0,
          step: 0.1
        )
        .id(testIdentity("DoubleSlider"))
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Amount"))
    #expect(surface.contains("Ratio"))
    #expect(surface.contains("0.2"))
    #expect(surface.contains("0.45"))
    #expect(!surface.contains("0.200000"))
    #expect(!surface.contains("0.449999"))
    #expect(actionRegistry.dispatch(identity: testIdentity("DoubleStepper")))
    #expect(stepperBox.value == 0.3)
    #expect(keyRegistry.dispatch(identity: testIdentity("DoubleSlider"), event: .arrowRight))
    #expect(sliderBox.value == 0.55)
  }

  @Test("Stepper renders its editing chrome directly from focus")
  func stepperRendersEditingChromeFromFocus() {
    func render(focused: Bool) -> RasterSurface {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = focused ? testIdentity("ActiveStepper") : nil
      return DefaultRenderer().render(
        Stepper("Count", value: .constant(1), in: 0...4)
          .id(testIdentity("ActiveStepper")),
        context: .init(
          identity: testIdentity("Root"),
          environmentValues: environmentValues
        )
      ).rasterSurface
    }

    #expect(render(focused: false) != render(focused: true))
  }

  @Test("Slider renders its editing chrome directly from focus")
  func sliderRendersEditingChromeFromFocus() {
    func render(focused: Bool) -> RasterSurface {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = focused ? testIdentity("ActiveSlider") : nil
      return DefaultRenderer().render(
        Slider("Value", value: .constant(2), in: 0...4)
          .id(testIdentity("ActiveSlider")),
        context: .init(
          identity: testIdentity("Root"),
          environmentValues: environmentValues
        )
      ).rasterSurface
    }

    #expect(render(focused: false) != render(focused: true))
  }

  @Test("focused Stepper and Slider share the row-control focus rail")
  func focusedAdjustableControlsUseSharedFocusRail() {
    func render<V: View>(
      id: Identity,
      _ view: V
    ) -> String {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = id
      return DefaultRenderer().render(
        view.id(id),
        context: .init(
          identity: testIdentity("Root"),
          environmentValues: environmentValues
        )
      ).rasterSurface.lines.joined(separator: "\n")
    }

    let stepperSurface = render(
      id: testIdentity("RailStepper"),
      Stepper("Count", value: .constant(1), in: 0...4)
    )
    let sliderSurface = render(
      id: testIdentity("RailSlider"),
      Slider("Value", value: .constant(2), in: 0...4)
    )

    #expect(stepperSurface.contains("▌ Count"))
    #expect(sliderSurface.contains("▌ Value"))
  }

  @Test("pressed Stepper and Slider do not introduce the focus rail")
  func pressedAdjustableControlsDoNotShowFocusRail() {
    func render<V: View>(
      id: Identity,
      _ view: V
    ) -> String {
      var environmentValues = EnvironmentValues()
      environmentValues.pressedIdentity = id
      return DefaultRenderer().render(
        view.id(id),
        context: .init(
          identity: testIdentity("Root"),
          environmentValues: environmentValues
        )
      ).rasterSurface.lines.joined(separator: "\n")
    }

    let stepperSurface = render(
      id: testIdentity("PressedRailStepper"),
      Stepper("Count", value: .constant(1), in: 0...4)
    )
    let sliderSurface = render(
      id: testIdentity("PressedRailSlider"),
      Slider("Value", value: .constant(2), in: 0...4)
    )

    #expect(!stepperSurface.contains("▌ Count"))
    #expect(!sliderSurface.contains("▌ Value"))
  }

  @Test(
    "TextField shows its prompt when idle, shows a cursor while active, and local key handling mutates the bound string"
  )
  func textFieldHandlesPromptCursorAndKeyInput() {
    final class TextBox {
      var value = ""
    }

    let box = TextBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("NameField")

    let focusedArtifacts = DefaultRenderer().render(
      TextField(
        "Name",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(testIdentity("NameField")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )
    let promptArtifacts = DefaultRenderer().render(
      TextField("Name", text: .constant("")),
      context: .init(identity: testIdentity("PromptField"))
    )

    #expect(
      focusedArtifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("NameField")])
    #expect(!focusedArtifacts.rasterSurface.lines.joined(separator: "\n").isEmpty)
    #expect(!promptArtifacts.rasterSurface.lines.joined(separator: "\n").isEmpty)

    #expect(registry.dispatch(identity: testIdentity("NameField"), event: .character("A")))
    #expect(box.value == "A")
    #expect(registry.dispatch(identity: testIdentity("NameField"), event: .space))
    #expect(box.value == "A ")
    #expect(registry.dispatch(identity: testIdentity("NameField"), event: .backspace))
    #expect(box.value == "A")
  }

  @Test("plain TextFieldStyle removes chrome while keeping active text entry visible")
  func plainTextFieldStyleRemovesChrome() {
    let artifacts = DefaultRenderer().render(
      TextField("Name", text: .constant("Ada"))
        .id(testIdentity("PlainField"))
        .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: {
          var values = EnvironmentValues()
          values.focusedIdentity = testIdentity("PlainField")
          return values
        }()
      )
    )

    #expect(artifacts.rasterSurface.lines == ["Ada_"])
  }

  @Test("roundedBorder TextField expands to fill an explicit frame width")
  func roundedBorderTextFieldFillsFrameWidth() {
    let artifacts = DefaultRenderer().render(
      TextField("Name", text: .constant("Ada"))
        .frame(width: 12, height: 3, alignment: .leading),
      context: .init(identity: testIdentity("WideField"))
    )

    let lines = artifacts.rasterSurface.lines
    #expect(lines.count == 3)
    #expect(lines.allSatisfy { $0.count == 12 || $0.isEmpty })
    #expect(lines.joined(separator: "\n").contains("╭"))
    #expect(lines.joined(separator: "\n").contains("╮"))
  }

  @Test("DisclosureGroup toggles expansion through the local action path and reveals its content")
  func disclosureGroupDispatchesLocalExpansionAction() {
    final class ExpansionBox {
      var isExpanded = false
    }

    let box = ExpansionBox()
    let registry = LocalActionRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("Disclosure")

    let collapsedArtifacts = DefaultRenderer().render(
      DisclosureGroup(
        "Options",
        isExpanded: Binding(
          get: { box.isExpanded },
          set: { box.isExpanded = $0 }
        )
      ) {
        Text("Detail")
      }
      .id(testIdentity("Disclosure")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let dispatched = registry.dispatch(identity: testIdentity("Disclosure"))

    let expandedArtifacts = DefaultRenderer().render(
      DisclosureGroup(
        "Options",
        isExpanded: Binding(
          get: { box.isExpanded },
          set: { box.isExpanded = $0 }
        )
      ) {
        Text("Detail")
      }
      .id(testIdentity("Disclosure")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(!collapsedArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Detail"))
    #expect(dispatched)
    #expect(box.isExpanded)
    #expect(expandedArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Detail"))
  }

  @Test("focused DisclosureGroup and Menu share the activation-row focus rail")
  func focusedActivationRowsUseSharedFocusRail() {
    func render<V: View>(
      id: Identity,
      _ view: V
    ) -> String {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = id
      return DefaultRenderer().render(
        view.id(id),
        context: .init(
          identity: testIdentity("Root"),
          environmentValues: environmentValues
        )
      ).rasterSurface.lines.joined(separator: "\n")
    }

    let disclosureSurface = render(
      id: testIdentity("RailDisclosure"),
      DisclosureGroup("Options", isExpanded: .constant(false)) {
        Text("Detail")
      }
    )
    let menuSurface = render(
      id: testIdentity("RailMenu"),
      Menu("Actions") {
        Button("Open") {}
      }
    )

    #expect(disclosureSurface.contains("▌ ▸ Options"))
    #expect(menuSurface.contains("▌ Actions"))
  }

  @Test("Picker uses tag metadata plus local key handling to update inline selection")
  func pickerUsesTagsAndArrowKeys() {
    final class SelectionBox {
      var value = 0
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("PresetPicker")

    let root = Picker(
      "Preset",
      selection: Binding(
        get: { box.value },
        set: { box.value = $0 }
      )
    ) {
      Text("Zero").tag(0)
      Text("Two").tag(2)
      Text("Four").tag(4)
    }
    .id(testIdentity("PresetPicker"))
    .pickerStyle(.inline)

    let artifacts = DefaultRenderer().render(
      root,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("PresetPicker")])
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("▌ Zero"))
    #expect(registry.dispatch(identity: testIdentity("PresetPicker"), event: .arrowDown))
    #expect(box.value == 2)
  }

  @Test("Picker supports optional tag matching and segmented left-right navigation")
  func pickerSupportsOptionalTagsAndSegmentedStyle() {
    final class SelectionBox {
      var value: Int? = 1
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("ModePicker")

    let artifacts = DefaultRenderer().render(
      Picker(
        "Mode",
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
      }
      .id(testIdentity("ModePicker"))
      .pickerStyle(.segmented),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Mode"))
    #expect(registry.dispatch(identity: testIdentity("ModePicker"), event: .arrowRight))
    #expect(box.value == 2)
  }

  @Test("Picker radioGroup style renders radio markers and uses vertical navigation")
  func pickerRadioGroupStyleRendersAndNavigates() {
    final class SelectionBox {
      var value = 1
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("RadioPicker")

    let artifacts = DefaultRenderer().render(
      Picker(
        "Mode",
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .id(testIdentity("RadioPicker"))
      .pickerStyle(.radioGroup),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("RadioPicker")])
    #expect(surface.contains("( ) Two"))
    #expect(registry.dispatch(identity: testIdentity("RadioPicker"), event: .arrowDown))
    #expect(box.value == 2)
  }

  @Test("Picker radioGroup preserves rounded inset corners across an explicit frame width")
  func pickerRadioGroupPreservesRoundedInsetCornersAcrossFrameWidth() {
    let artifacts = DefaultRenderer().render(
      Picker("Mode", selection: .constant(1)) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .pickerStyle(.radioGroup)
      .frame(width: 18, alignment: .leading),
      context: .init(identity: testIdentity("FramedRadioPicker"))
    )

    let selectedRow = artifacts.rasterSurface.cells[2]
    #expect(selectedRow[1].style?.backgroundColor == nil)
    #expect(selectedRow[14].style?.backgroundColor != nil)
  }

  @Test("Picker radioGroup preserves its label and leading option under vertical stack compression")
  func pickerRadioGroupPreservesTopRowsUnderCompression() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Top")
          .frame(width: 18, height: 1, alignment: .leading)
        Picker("Mode", selection: .constant(1)) {
          Text("One").tag(1)
          Text("Two").tag(2)
          Text("Three").tag(3)
        }
        .pickerStyle(.radioGroup)
      }
      .frame(width: 18, height: 5, alignment: .topLeading),
      context: .init(identity: testIdentity("CompressedRadioPicker"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Mode"))
  }

  @Test(
    "Picker menu style collapses by default, expands when focused, and uses vertical navigation")
  func pickerMenuStyleCollapsesExpandsAndNavigates() {
    final class SelectionBox {
      var value = 1
    }

    let box = SelectionBox()
    let collapsedArtifacts = DefaultRenderer().render(
      Picker(
        "Mode",
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .id(testIdentity("MenuPicker"))
      .pickerStyle(.menu),
      context: .init(identity: testIdentity("CollapsedMenuPicker"))
    )

    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("MenuPicker")
    let expandedArtifacts = DefaultRenderer().render(
      Picker(
        "Mode",
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .id(testIdentity("MenuPicker"))
      .pickerStyle(.menu),
      context: .init(
        identity: testIdentity("ExpandedMenuPicker"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let collapsedSurface = collapsedArtifacts.rasterSurface.lines.joined(separator: "\n")
    let expandedSurface = expandedArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(collapsedSurface.contains("▾"))
    #expect(collapsedSurface.contains("One"))
    #expect(!collapsedSurface.contains("Two"))
    #expect(
      expandedArtifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("MenuPicker")
      ])
    #expect(expandedSurface.contains("▌ ▴"))
    #expect(expandedSurface.contains("▴"))
    #expect(expandedSurface.contains("Two"))
    #expect(expandedSurface.contains("Three"))
    #expect(registry.dispatch(identity: testIdentity("MenuPicker"), event: .arrowDown))
    #expect(box.value == 2)
  }

  @Test("focused radioGroup Picker reuses the shared row-selection rail")
  func focusedRadioGroupPickerUsesSharedSelectionRail() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("RadioRailPicker")

    let surface = DefaultRenderer().render(
      Picker("Mode", selection: .constant(2)) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .id(testIdentity("RadioRailPicker"))
      .pickerStyle(.radioGroup),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    ).rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("▌ (*) Two"))
  }

  @Test("Picker inline, segmented, and radioGroup styles render editing chrome directly from focus")
  func pickerStylesRenderEditingChromeDirectlyFromFocus() {
    func renderPicker(
      id: Identity,
      style: AnyPickerStyle
    ) -> (unfocused: RasterSurface, focused: RasterSurface) {
      let picker =
        Picker("Mode", selection: .constant(1)) {
          Text("One").tag(1)
          Text("Two").tag(2)
          Text("Three").tag(3)
        }
        .id(id)
        .pickerStyle(style)

      let unfocused = DefaultRenderer().render(
        picker,
        context: .init(
          identity: testIdentity("Unfocused\(id)")
        )
      ).rasterSurface
      var focusedValues = EnvironmentValues()
      focusedValues.focusedIdentity = id
      let focused = DefaultRenderer().render(
        picker,
        context: .init(
          identity: testIdentity("Focused\(id)"),
          environmentValues: focusedValues
        )
      ).rasterSurface
      return (unfocused, focused)
    }

    let inline = renderPicker(id: testIdentity("InlinePicker"), style: .inline)
    let segmented = renderPicker(id: testIdentity("SegmentedPicker"), style: .segmented)
    let radioGroup = renderPicker(id: testIdentity("RadioPickerStyles"), style: .radioGroup)

    #expect(inline.unfocused != inline.focused)
    #expect(segmented.unfocused != segmented.focused)
    #expect(radioGroup.unfocused != radioGroup.focused)
  }

  @Test("inline Picker viewport markers derive from the internal viewport line count hook")
  func pickerViewportMarkersStayDeterministic() {
    let artifacts = DefaultRenderer().render(
      Picker(selection: .constant(2)) {
        ForEach(0..<8) { index in
          Text("Option \(index)").tag(index)
        }
      } label: {
        EmptyView()
      }
      .pickerViewportLineCount(5)
      .pickerStyle(.inline),
      context: .init(identity: testIdentity("ViewportPicker"))
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("↑"))
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("↓"))
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("▌ Option 2"))
  }

  @Test("List uses tag metadata plus local key handling to update row selection")
  func listUsesTagsAndArrowKeys() {
    final class SelectionBox {
      var value = 0
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("PresetList")

    let artifacts = DefaultRenderer().render(
      List(
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("Zero").tag(0)
        Text("Two").tag(2)
        Text("Four").tag(4)
      }
      .id(testIdentity("PresetList"))
      .listStyle(.insetGrouped),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("PresetList")])
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("▌ Zero"))
    #expect(registry.dispatch(identity: testIdentity("PresetList"), event: .arrowDown))
    #expect(box.value == 2)
  }

  @Test("plain List leaves Section headers and footers unobscured inline with tagged row content")
  func listRendersSectionHeaders() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("SectionList")

    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Section {
          Text("One").tag(1)
          Text("Two").tag(2)
        } header: {
          Text("Primary")
        } footer: {
          Text("Footer")
        }
      }
      .listStyle(.plain),
      context: .init(
        identity: testIdentity("SectionList"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Primary"))
    #expect(surface.contains("▌ One"))
    #expect(surface.contains("  Two"))
    #expect(surface.contains("Footer"))
    #expect(!surface.contains("┌"))
  }

  @Test("insetGrouped List preserves grouped chrome while rendering multiple sections")
  func insetGroupedListRendersGroupedChromeAndSections() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("GroupedList")

    let artifacts = DefaultRenderer().render(
      List(selection: .constant(2)) {
        Section("Primary") {
          Text("One").tag(1)
          Text("Two").tag(2)
        }
        Section("Secondary") {
          Text("Three").tag(3)
        }
      }
      .listStyle(.insetGrouped),
      context: .init(
        identity: testIdentity("GroupedList"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let lines = artifacts.rasterSurface.lines
    #expect(lines.filter { $0.contains("╭") }.count == 2)
    #expect(surface.contains("Primary"))
    #expect(surface.contains("Secondary"))
    #expect(surface.contains("▌ Two"))
  }

  @Test("listRowSeparator hides plain-list separators on requested edges")
  func listRowSeparatorHidesRequestedEdges() {
    var defaultEnvironment = EnvironmentValues()
    defaultEnvironment.focusedIdentity = testIdentity("DefaultRowSeparators")
    let defaultArtifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Text("One").tag(1)
        Text("Two").tag(2)
      }
      .listStyle(.plain),
      context: .init(
        identity: testIdentity("DefaultRowSeparators"),
        environmentValues: defaultEnvironment
      )
    )
    var hiddenEnvironment = EnvironmentValues()
    hiddenEnvironment.focusedIdentity = testIdentity("HiddenRowSeparators")
    let hiddenArtifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Text("One")
          .tag(1)
          .listRowSeparator(.hidden, edges: .bottom)
        Text("Two").tag(2)
      }
      .listStyle(.plain),
      context: .init(
        identity: testIdentity("HiddenRowSeparators"),
        environmentValues: hiddenEnvironment
      )
    )

    let defaultSurface = defaultArtifacts.rasterSurface.lines.joined(separator: "\n")
    let hiddenSurface = hiddenArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(defaultSurface.contains("─"))
    #expect(!hiddenSurface.contains("─"))
    #expect(hiddenSurface.contains("▌ One"))
    #expect(hiddenSurface.contains("  Two"))
  }

  @Test("listSectionSeparator hides plain-list section breaks on requested edges")
  func listSectionSeparatorHidesRequestedEdges() {
    let defaultArtifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Section("Primary") {
          Text("One").tag(1)
        }
        Section("Secondary") {
          Text("Two").tag(2)
        }
      }
      .listStyle(.plain),
      context: .init(identity: testIdentity("DefaultSectionSeparators"))
    )
    let hiddenArtifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Section("Primary") {
          Text("One").tag(1)
        }
        .listSectionSeparator(.hidden, edges: .bottom)

        Section("Secondary") {
          Text("Two").tag(2)
        }
      }
      .listStyle(.plain),
      context: .init(identity: testIdentity("HiddenSectionSeparators"))
    )

    let defaultSurface = defaultArtifacts.rasterSurface.lines.joined(separator: "\n")
    let hiddenSurface = hiddenArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(defaultSurface.contains("─"))
    #expect(!hiddenSurface.contains("─"))
    #expect(hiddenSurface.contains("Primary"))
    #expect(hiddenSurface.contains("Secondary"))
  }

  @Test("List viewport markers derive from actual bounds")
  func listViewportMarkersStayDeterministic() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("ViewportListControl")

    let artifacts = DefaultRenderer().render(
      List(selection: .constant(2)) {
        ForEach(0..<8) { index in
          Text("Option \(index)").tag(index)
        }
      }
      .listStyle(.insetGrouped)
      .id(testIdentity("ViewportListControl"))
      .frame(width: 20, height: 7, alignment: .topLeading),
      context: .init(
        identity: testIdentity("ViewportList"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("↑"))
    #expect(surface.contains("↓"))
    #expect(surface.contains("▌ Option 2"))
  }

  @Test(
    "List scrollIndicators hidden suppresses viewport markers without changing the selected row")
  func listScrollIndicatorsCanBeHidden() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("HiddenViewportListControl")

    let artifacts = DefaultRenderer().render(
      List(selection: .constant(2)) {
        ForEach(0..<8) { index in
          Text("Option \(index)").tag(index)
        }
      }
      .listStyle(.insetGrouped)
      .scrollIndicators(.hidden)
      .id(testIdentity("HiddenViewportListControl"))
      .frame(width: 20, height: 7, alignment: .topLeading),
      context: .init(
        identity: testIdentity("HiddenViewportList"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(!surface.contains("^ more"))
    #expect(!surface.contains("v more"))
    #expect(surface.contains("▌ Option 2"))
  }

  @Test("listRowBackground fills an unselected row without changing list selection chrome")
  func listRowBackgroundFillsCustomRows() {
    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Text("One").tag(1)
        Text("Two")
          .tag(2)
          .listRowBackground(Color.red)
      }
      .listStyle(.plain),
      context: .init(identity: testIdentity("RowBackgroundList"))
    )

    #expect(artifacts.rasterSurface.lines[2].contains("Two"))
    #expect(artifacts.rasterSurface.cells[2][0].style?.backgroundColor == Color.red)
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor != Color.red)
  }

  @Test("listRowForegroundStyle overrides the text color for an unselected row")
  func listRowForegroundStyleOverridesRowTextColor() {
    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Text("One").tag(1)
        Text("Two")
          .tag(2)
          .listRowForegroundStyle(Color.yellow)
      }
      .listStyle(.plain),
      context: .init(identity: testIdentity("RowForegroundList"))
    )

    #expect(artifacts.rasterSurface.lines[2].contains("Two"))
    #expect(artifacts.rasterSurface.cells[2][2].style?.foregroundColor == Color.yellow)
  }

  @Test("Table uses tagged rows plus local key handling to update row selection")
  func tableUsesTagsAndArrowKeys() {
    final class SelectionBox {
      var value = "alpha"
    }

    let box = SelectionBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("MetricsTable")

    let artifacts = DefaultRenderer().render(
      Table(
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        ),
        columns: [
          .init("Name", width: 8),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("Alpha")
          Text("10")
        }
        .tag("alpha")
        TableRow {
          Text("Beta")
          Text("25")
        }
        .tag("beta")
      }
      .id(testIdentity("MetricsTable")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("MetricsTable")])
    #expect(surface.contains("Name"))
    #expect(surface.contains("│ Alpha"))
    #expect(registry.dispatch(identity: testIdentity("MetricsTable"), event: .arrowDown))
    #expect(box.value == "beta")
  }

  @Test("Table renders headers, separators, and explicit-width truncation")
  func tableRendersHeadersAndTruncatesCells() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("TruncatingTable")

    let artifacts = DefaultRenderer().render(
      Table(
        selection: .constant(1),
        columns: [
          .init("Metric", width: 6),
          .init("Value", width: 4, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("LongLabel")
          Text("12345")
        }
        .tag(1)
        TableRow {
          Text("Short")
          Text("7")
        }
        .tag(2)
      },
      context: .init(
        identity: testIdentity("TruncatingTable"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Metric"))
    #expect(surface.contains("╭"))
    #expect(surface.contains("LongL…"))
    #expect(surface.contains("123…"))
    #expect(surface.contains("│ LongL…"))
  }

  @Test("Table resolves to a structured row-and-cell payload")
  func tableResolvesToStructuredPayload() {
    let artifacts = DefaultRenderer().render(
      Table(
        selection: .constant(2),
        columns: [
          .init("Metric", width: 6),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("Alpha").foregroundStyle(Color.yellow)
          Text("10")
        }
        .tag(1)

        TableRow {
          Text("Beta")
          Text("25").bold()
        }
        .tag(2)
      },
      context: .init(identity: testIdentity("StructuredTable"))
    )

    guard case .table(let payload) = artifacts.resolvedTree.drawPayload else {
      Issue.record("Expected Table to resolve to a structured table payload")
      return
    }

    #expect(payload.columns.map(\.title) == ["Metric", "Value"])
    #expect(payload.rows.map { $0.cells.map(\.text) } == [["Alpha", "10"], ["Beta", "25"]])
    #expect(payload.selectedRowIndex == 1)
    #expect(payload.rows[0].cells[0].style.foregroundStyle == .color(Color.yellow))
    #expect(payload.rows[1].cells[1].style.emphasis.contains(.bold))
  }

  @Test("Table carries row styling modifiers through the structured table draw path")
  func tableCarriesRowStylingMetadata() {
    let artifacts = DefaultRenderer().render(
      Table(
        selection: .constant(1),
        columns: [
          .init("Metric", width: 6),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("Alpha")
          Text("10")
        }
        .tag(1)
        .listRowSeparator(.hidden, edges: .bottom)

        TableRow {
          Text("Beta")
          Text("25")
        }
        .tag(2)
        .listRowBackground(Color.red)
        .listRowForegroundStyle(Color.yellow)
      }
      .listStyle(.plain),
      context: .init(identity: testIdentity("StyledTable"))
    )

    let separatorLines = artifacts.rasterSurface.lines.filter { $0.contains("─") }
    #expect(separatorLines.count == 3)
    #expect(artifacts.rasterSurface.lines[4].contains("Beta"))
    #expect(artifacts.rasterSurface.cells[4][0].style?.backgroundColor == Color.red)
    #expect(artifacts.rasterSurface.cells[4][2].style?.foregroundColor == Color.yellow)
  }

  @Test("Table respects listStyle and scrollIndicators environment controls")
  func tableHonorsListChromeAndIndicatorVisibility() {
    var visibleEnvironment = EnvironmentValues()
    visibleEnvironment.focusedIdentity = testIdentity("VisibleGroupedTableControl")
    let visibleArtifacts = DefaultRenderer().render(
      Table(
        selection: .constant(3),
        columns: [
          .init("Metric", width: 8),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        ForEach(0..<8) { index in
          TableRow {
            Text("Item \(index)")
            Text("\(index)")
          }
          .tag(index)
        }
      }
      .listStyle(.insetGrouped)
      .id(testIdentity("VisibleGroupedTableControl"))
      .frame(width: 20, height: 7, alignment: .topLeading),
      context: .init(
        identity: testIdentity("VisibleGroupedTable"),
        environmentValues: visibleEnvironment
      )
    )
    var hiddenEnvironment = EnvironmentValues()
    hiddenEnvironment.focusedIdentity = testIdentity("HiddenGroupedTableControl")
    let hiddenArtifacts = DefaultRenderer().render(
      Table(
        selection: .constant(3),
        columns: [
          .init("Metric", width: 8),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        ForEach(0..<8) { index in
          TableRow {
            Text("Item \(index)")
            Text("\(index)")
          }
          .tag(index)
        }
      }
      .listStyle(.insetGrouped)
      .scrollIndicators(.hidden)
      .id(testIdentity("HiddenGroupedTableControl"))
      .frame(width: 20, height: 7, alignment: .topLeading),
      context: .init(
        identity: testIdentity("HiddenGroupedTable"),
        environmentValues: hiddenEnvironment
      )
    )

    let visibleSurface = visibleArtifacts.rasterSurface.lines.joined(separator: "\n")
    let hiddenSurface = hiddenArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(visibleSurface.contains("╭"))
    #expect(visibleSurface.contains("↑"))
    #expect(hiddenSurface.contains("╭"))
    #expect(!hiddenSurface.contains("↑"))
    #expect(hiddenSurface.contains("Item 3"))
  }

  @Test("Table headers can be hidden through the environment-driven surface")
  func tableHeadersCanBeHidden() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("HeaderlessTable")

    let artifacts = DefaultRenderer().render(
      Table(
        selection: .constant(2),
        columns: [
          .init("Metric", width: 6),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("Alpha")
          Text("10")
        }
        .tag(1)
        TableRow {
          Text("Beta")
          Text("25")
        }
        .tag(2)
      }
      .tableHeaders(.hidden),
      context: .init(
        identity: testIdentity("HeaderlessTable"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(!surface.contains("Metric"))
    #expect(artifacts.rasterSurface.lines[0] == "╭────────┬───────╮")
    #expect(artifacts.rasterSurface.lines[1] == "│ Alpha  │    10 │")
    #expect(surface.contains("│ Beta"))
  }

  @Test("Table columns can align header titles independently from cell content")
  func tableColumnHeaderAlignmentCanDifferFromCellAlignment() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("HeaderAlignmentTable")

    let artifacts = DefaultRenderer().render(
      Table(
        selection: .constant(1),
        columns: [
          .init("Name", width: 8, alignment: .leading, titleAlignment: .center),
          .init("Value", width: 5, alignment: .trailing, titleAlignment: .leading),
        ]
      ) {
        TableRow {
          Text("Alpha")
          Text("7")
        }
        .tag(1)
      },
      context: .init(
        identity: testIdentity("HeaderAlignmentTable"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines[1] == "│   Name   │ Value │")
    #expect(artifacts.rasterSurface.lines[3] == "│ Alpha    │     7 │")
  }

  @Test("read-only Table skips focus and selection markers while still rendering rows")
  func readOnlyTableSkipsSelectionChrome() {
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("ReadOnlyTable")

    let artifacts = DefaultRenderer().render(
      Table(
        columns: [
          .init("Metric", width: 6),
          .init("Value", width: 5, alignment: .trailing),
        ]
      ) {
        TableRow {
          Text("Alpha")
          Text("10")
        }
        TableRow {
          Text("Beta")
          Text("25")
        }
      }
      .id(testIdentity("ReadOnlyTable")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.semanticSnapshot.focusRegions.isEmpty)
    #expect(!registry.dispatch(identity: testIdentity("ReadOnlyTable"), event: .arrowDown))
    #expect(surface.contains("Alpha"))
    #expect(surface.contains("Beta"))
    #expect(!surface.contains("| Alpha"))
    #expect(!surface.contains("| Beta"))
  }

  @Test("List and Table render editing chrome directly from focus")
  func listAndTableRenderEditingChromeDirectlyFromFocus() {
    func renderList(focused: Bool) -> RasterSurface {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = focused ? testIdentity("ActiveList") : nil
      return DefaultRenderer().render(
        List(selection: .constant(1)) {
          Text("One").tag(1)
          Text("Two").tag(2)
        }
        .id(testIdentity("ActiveList"))
        .listStyle(.plain),
        context: .init(
          identity: testIdentity("ListRoot"),
          environmentValues: environmentValues
        )
      ).rasterSurface
    }

    func renderTable(focused: Bool) -> RasterSurface {
      var environmentValues = EnvironmentValues()
      environmentValues.focusedIdentity = focused ? testIdentity("ActiveTable") : nil
      return DefaultRenderer().render(
        Table(
          selection: .constant(1),
          columns: [
            .init("Name", width: 6),
            .init("Value", width: 5, alignment: .trailing),
          ]
        ) {
          TableRow {
            Text("One")
            Text("1")
          }
          .tag(1)
          TableRow {
            Text("Two")
            Text("2")
          }
          .tag(2)
        }
        .id(testIdentity("ActiveTable")),
        context: .init(
          identity: testIdentity("TableRoot"),
          environmentValues: environmentValues
        )
      ).rasterSurface
    }

    let unfocusedList = renderList(focused: false)
    let focusedList = renderList(focused: true)
    #expect(unfocusedList != focusedList)
    #expect(!unfocusedList.lines.joined(separator: "\n").contains("▌ One"))
    #expect(focusedList.lines.joined(separator: "\n").contains("▌ One"))

    let unfocusedTable = renderTable(focused: false)
    let focusedTable = renderTable(focused: true)
    #expect(unfocusedTable != focusedTable)
    #expect(unfocusedTable.lines.joined(separator: "\n").contains("│ One"))
    #expect(focusedTable.lines.joined(separator: "\n").contains("│ One"))
    #expect(unfocusedTable.cells[3][2].style != focusedTable.cells[3][2].style)
  }

  @Test("ScrollView clips overflow to its viewport and reports larger semantic content bounds")
  func scrollViewClipsAndReportsContentBounds() throws {
    let artifacts = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          Text("One  ")
          Text("Two  ")
          Text("Three")
        }
      }
      .frame(width: 5, height: 2, alignment: .topLeading),
      context: .init(identity: testIdentity("ScrollViewport"))
    )

    let route = try #require(artifacts.semanticSnapshot.scrollRoutes.first)

    #expect(
      artifacts.rasterSurface.lines.prefix(2) == [
        "One  ",
        "Two  ",
      ])
    #expect(artifacts.rasterSurface.lines.dropFirst(2).allSatisfy { $0.isEmpty })
    #expect(route.viewportRect.size == .init(width: 5, height: 2))
    #expect(route.contentBounds.size == .init(width: 5, height: 3))
  }

  @Test("framed ScrollView fills the remaining preview panel height")
  func framedScrollViewFillsTheRemainingPreviewPanelHeight() throws {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Title")
        Divider()
        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
              Text("Row \(index)")
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Spacer(minLength: 0)
      }
      .frame(width: 8, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("ScrollFillPanel"))
    )

    let route = try #require(artifacts.semanticSnapshot.scrollRoutes.first)

    #expect(route.viewportRect.size == .init(width: 8, height: 6))
    #expect(route.contentBounds.size.height == 8)
  }

  @Test("Lazy stacks outside ScrollView match their eager counterparts")
  func lazyStacksOutsideScrollViewMatchTheirEagerCounterparts() {
    let eagerVertical = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("One")
        Text("Two")
      },
      context: .init(identity: testIdentity("EagerVertical"))
    ).rasterSurface

    let lazyVertical = DefaultRenderer().render(
      LazyVStack(alignment: .leading, spacing: 0) {
        Text("One")
        Text("Two")
      },
      context: .init(identity: testIdentity("LazyVertical"))
    ).rasterSurface

    let eagerHorizontal = DefaultRenderer().render(
      HStack(alignment: .center, spacing: 1) {
        Text("A")
        Text("B")
      },
      context: .init(identity: testIdentity("EagerHorizontal"))
    ).rasterSurface

    let lazyHorizontal = DefaultRenderer().render(
      LazyHStack(alignment: .center, spacing: 1) {
        Text("A")
        Text("B")
      },
      context: .init(identity: testIdentity("LazyHorizontal"))
    ).rasterSurface

    #expect(lazyVertical == eagerVertical)
    #expect(lazyHorizontal == eagerHorizontal)
  }

  @Test("LazyVStack clips overflow to its viewport and reports larger semantic content bounds")
  func lazyVerticalStackClipsAndReportsContentBounds() throws {
    let artifacts = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("One  ")
          Text("Two  ")
          Text("Three")
        }
      }
      .frame(width: 5, height: 2, alignment: .topLeading),
      context: .init(identity: testIdentity("LazyScrollViewport"))
    )

    let route = try #require(artifacts.semanticSnapshot.scrollRoutes.first)

    #expect(
      artifacts.rasterSurface.lines.prefix(2) == [
        "One  ",
        "Two  ",
      ])
    #expect(artifacts.rasterSurface.lines.dropFirst(2).allSatisfy { $0.isEmpty })
    #expect(route.viewportRect.size == .init(width: 5, height: 2))
    #expect(route.contentBounds.size == .init(width: 5, height: 3))
  }

  @Test("scroll position changes do not emit lifecycle deltas for lazy stacks")
  func lazyStackScrollPositionChangesDoNotEmitLifecycleDeltas() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
          .onAppear {}
          .onDisappear {}
          .task(id: "row-2") {}
      }
    }
    .frame(width: 5, height: 2, alignment: .topLeading)

    let renderer = DefaultRenderer()

    _ = renderer.render(
      view,
      context: .init(identity: testIdentity("LazyScrollRoot"))
    )

    box.position.scrollBy(y: 1)

    let scrolledArtifacts = renderer.render(
      view,
      context: .init(identity: testIdentity("LazyScrollRoot"))
    )

    #expect(scrolledArtifacts.rasterSurface.lines.prefix(2) == ["Row 1", "Row 2"])
    #expect(scrolledArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("lazy stacks scope focus and interaction to the visible viewport")
  func lazyStacksScopeFocusAndInteractionToViewport() {
    let visibleIdentity = testIdentity("VisibleButton")
    let hiddenIdentity = testIdentity("HiddenButton")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = visibleIdentity

    let artifacts = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 0) {
          Button("Visible") {}
            .id(visibleIdentity)
          Text("Spacer 1")
          Text("Spacer 2")
          Button("Hidden") {}
            .id(hiddenIdentity)
          Text("Tail")
        }
      }
      .frame(width: 12, height: 1, alignment: .topLeading),
      context: .init(
        identity: testIdentity("ViewportScope"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.rasterSurface.lines.first?.contains("Visible") == true)
    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(visibleIdentity))
    #expect(!artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(hiddenIdentity))
    #expect(artifacts.semanticSnapshot.interactionRegions.map(\.identity).contains(visibleIdentity))
    #expect(!artifacts.semanticSnapshot.interactionRegions.map(\.identity).contains(hiddenIdentity))
  }

  @Test("single-ForEach lazy stacks emit viewport lifecycle transitions as rows enter and leave")
  func lazyForEachRowsEmitViewportLifecycleTransitions() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let rows = (0..<4).map {
      PaletteRow(id: "row-\($0)", label: "Row \($0)")
    }
    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        Group {
          ForEach(rows) { row in
            Text(row.label)
              .onAppear {}
              .onDisappear {}
              .task(id: row.id) {}
          }
        }
      }
    }
    .frame(width: 5, height: 2, alignment: .topLeading)

    let renderer = DefaultRenderer()

    let initialArtifacts = renderer.render(
      view,
      context: .init(identity: testIdentity("LazyForEachScrollRoot"))
    )

    #expect(initialArtifacts.rasterSurface.lines.prefix(2) == ["Row 0", "Row 1"])

    box.position.scrollBy(y: 1)

    let scrolledArtifacts = renderer.render(
      view,
      context: .init(identity: testIdentity("LazyForEachScrollRoot"))
    )

    let operations = scrolledArtifacts.commitPlan.lifecycle.map(\.operation)

    #expect(scrolledArtifacts.rasterSurface.lines.prefix(2) == ["Row 1", "Row 2"])
    #expect(operations.count == 4)
    #expect(isTaskCancel(operations[0]))
    #expect(isDisappear(operations[1]))
    #expect(isAppear(operations[2]))
    #expect(isTaskStart(operations[3]))
  }

  @Test("mixed static siblings keep LazyVStack on the stable lifecycle path")
  func lazyVStackWithMixedStaticSiblingsKeepsStableLifecycleDuringScroll() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      LazyVStack(alignment: .leading, spacing: 0) {
        Text("Top")
        ForEach(0..<3) { index in
          Text("Row \(index)")
            .onAppear {}
            .onDisappear {}
            .task(id: "row-\(index)") {}
        }
        Text("End")
      }
    }
    .frame(width: 5, height: 2, alignment: .topLeading)

    let renderer = DefaultRenderer()

    _ = renderer.render(
      view,
      context: .init(identity: testIdentity("MixedLazyStackRoot"))
    )

    box.position.scrollBy(y: 1)

    let scrolledArtifacts = renderer.render(
      view,
      context: .init(identity: testIdentity("MixedLazyStackRoot"))
    )

    #expect(scrolledArtifacts.rasterSurface.lines.prefix(2) == ["Row 0", "Row 1"])
    #expect(scrolledArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("ScrollPosition helper APIs support incremental and absolute updates")
  func scrollPositionHelpersApplyDirectionalChanges() {
    var position = ScrollPosition.zero

    position.scrollBy(x: 2, y: 3)
    #expect(position == .init(x: 2, y: 3))

    let advanced = position.scrolledBy(x: -1, y: 4)
    #expect(advanced == .init(x: 1, y: 7))
    #expect(position == .init(x: 2, y: 3))

    position.scrollTo(y: 1)
    #expect(position == .init(x: 2, y: 1))
  }

  @Test("ScrollView renders indicator chrome by default and respects the scrollIndicators modifier")
  func scrollViewIndicatorsRespectVisibility() {
    let baseView =
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("One ")
          Text("Two ")
          Text("Tre ")
        }
      }
      .frame(width: 5, height: 2, alignment: .topLeading)

    let visibleArtifacts = DefaultRenderer().render(
      baseView,
      context: .init(identity: testIdentity("VisibleScrollViewport"))
    )
    let hiddenArtifacts = DefaultRenderer().render(
      baseView.scrollIndicators(.hidden),
      context: .init(identity: testIdentity("HiddenScrollViewport"))
    )

    #expect(visibleArtifacts.resolvedTree.semanticMetadata.presentationRole == nil)
    #expect(visibleArtifacts.semanticSnapshot.scrollRoutes.count == 1)
    #expect(visibleArtifacts.rasterSurface.lines[1].hasSuffix("▼"))
    #expect(!hiddenArtifacts.rasterSurface.lines[1].hasSuffix("▼"))
    #expect(hiddenArtifacts.rasterSurface.lines.prefix(2) == ["One ", "Two "])
  }

  @Test("ScrollView indicator thumb scales with the visible-content ratio")
  func scrollViewIndicatorThumbScalesWithVisibleContentRatio() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let view = ScrollView(
      .vertical,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<10) { index in
          Text("Row \(index)")
        }
      }
    }
    .id(testIdentity("ProportionalScroll"))
    .frame(width: 8, height: 5, alignment: .topLeading)

    let topArtifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    box.position.scrollTo(y: 5)

    let bottomArtifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    let topThumbColumn = topArtifacts.rasterSurface.cells.prefix(5).map { row in
      row[7].character
    }
    let bottomThumbColumn = bottomArtifacts.rasterSurface.cells.prefix(5).map { row in
      row[7].character
    }

    #expect(topThumbColumn == ["█", "█", "█", "┃", "▼"])
    #expect(bottomThumbColumn == ["▲", "┃", "█", "█", "█"])
  }

  @Test("ScrollView indicator keeps a usable thumb size for large content")
  func scrollViewIndicatorThumbMaintainsMinimumDragTargetForLargeContent() {
    let view =
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<100) { index in
            Text("Row \(index)")
          }
        }
      }
      .id(testIdentity("LargeScroll"))
      .frame(width: 8, height: 6, alignment: .topLeading)

    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    let thumbColumn = artifacts.rasterSurface.cells.prefix(6).map { row in
      row[7].character
    }

    #expect(thumbColumn == ["█", "█", "█", "┃", "┃", "▼"])
  }

  @Test("ScrollView indicator focus highlights only the indicator")
  func scrollViewIndicatorFocusHighlightsOnlyTheIndicator() {
    let view =
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
        }
      }
      .id(testIdentity("Scrollable"))
      .frame(width: 6, height: 3, alignment: .topLeading)

    let idleArtifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = verticalScrollIndicatorIdentity(
      for: testIdentity("Scrollable")
    )
    let focusedArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(focusedArtifacts.rasterSurface.cells[0][0].style?.backgroundColor == nil)
    #expect(focusedArtifacts.rasterSurface.cells[1][1].style?.backgroundColor == nil)
    #expect(focusedArtifacts.rasterSurface.cells[1][5].style?.backgroundColor == nil)
    #expect(
      idleArtifacts.rasterSurface.cells[1][5].style?.foregroundColor
        != focusedArtifacts.rasterSurface.cells[1][5].style?.foregroundColor
    )
  }

  @Test("focused controls inside a ScrollView keep their own focus chrome")
  func focusedControlsInsideScrollViewKeepTheirOwnFocusChrome() {
    let view =
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          Button("Go") {}
            .id(testIdentity("InnerButton"))
          Text("Row 1")
          Text("Row 2")
        }
      }
      .id(testIdentity("Scrollable"))
      .frame(width: 7, height: 4, alignment: .topLeading)

    let unfocused = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root"))
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("InnerButton")
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("Scrollable"), testIdentity("InnerButton"),
      ])
    #expect(unfocused.rasterSurface.lines == artifacts.rasterSurface.lines)
    #expect(unfocused.rasterSurface != artifacts.rasterSurface)
  }

  @Test("overflowing ScrollView indicators are focusable and handle arrow-key scrolling")
  func scrollViewIndicatorsCanBeFocusedAndScrolledWithKeys() {
    final class ScrollBox {
      var position = ScrollPosition.zero
    }

    let box = ScrollBox()
    let registry = LocalKeyHandlerRegistry()
    let indicatorIdentity = verticalScrollIndicatorIdentity(for: testIdentity("Scrollable"))
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = indicatorIdentity

    let view = ScrollView(
      .vertical,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
        Text("Row 3")
        Text("Row 4")
      }
    }
    .id(testIdentity("Scrollable"))
    .frame(width: 6, height: 3, alignment: .topLeading)

    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("Scrollable"), indicatorIdentity,
      ])
    #expect(registry.dispatch(identity: indicatorIdentity, event: .arrowDown))
    #expect(box.position == .init(x: 0, y: 1))
  }

  @Test("ScrollView is a focusable view that handles arrow-key scrolling")
  func scrollViewBindsPositionAndHandlesArrowKeys() {
    final class ScrollBox {
      var position = ScrollPosition()
    }

    let box = ScrollBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("Scrollable")

    let view = ScrollView(
      .vertical,
      showsIndicators: false,
      position: Binding(
        get: { box.position },
        set: { box.position = $0 }
      )
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Row 0")
        Text("Row 1")
        Text("Row 2")
      }
    }
    .id(testIdentity("Scrollable"))
    .frame(width: 5, height: 2, alignment: .topLeading)

    let initialArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      initialArtifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("Scrollable")]
    )
    #expect(initialArtifacts.rasterSurface.lines.prefix(2) == ["Row 0", "Row 1"])
    #expect(registry.dispatch(identity: testIdentity("Scrollable"), event: .arrowDown))
    #expect(box.position == .init(x: 0, y: 1))

    let scrolledArtifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(scrolledArtifacts.rasterSurface.lines.prefix(2) == ["Row 1", "Row 2"])
  }

  @Test("ScrollView can be opted into focus explicitly when it needs a standalone surface")
  func scrollViewCanBeOptedIntoFocusExplicitly() {
    let artifacts = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
        }
      }
      .focusable()
      .id(testIdentity("Scrollable"))
      .frame(width: 5, height: 2, alignment: .topLeading),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("Scrollable")])
  }

  @Test("ScrollView renders its editing viewport state directly from focus")
  func scrollViewRendersEditingViewportStateDirectlyFromFocus() {
    let view =
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
        }
      }
      .id(testIdentity("ActiveScroll"))
      .frame(width: 5, height: 2, alignment: .topLeading)

    let unfocused = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("UnfocusedScrollRoot")
      )
    ).rasterSurface

    var focusedValues = EnvironmentValues()
    focusedValues.focusedIdentity = testIdentity("ActiveScroll")
    let focused = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("FocusedScrollRoot"),
        environmentValues: focusedValues
      )
    ).rasterSurface

    #expect(unfocused == focused)
  }

  @Test("Button resolves built-in control chrome, focus semantics, and action role routing")
  func buttonResolvesBuiltInControlChromeAndSemantics() {
    var environmentValues = EnvironmentValues()
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    environmentValues.terminalAppearance = appearance
    environmentValues.focusedIdentity = testIdentity("DeleteButton")
    final class TapBox {
      var didTap = false
    }
    let tapBox = TapBox()
    let actionRegistry = LocalActionRegistry()

    let artifacts = DefaultRenderer().render(
      Button(
        role: .destructive,
        action: {
          tapBox.didTap = true
        }
      ) {
        Text("Delete")
          .frame(width: 6, height: 1, alignment: .center)
      }
      .id(testIdentity("DeleteButton"))
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let plainArtifacts = DefaultRenderer().render(
      Button(
        role: .destructive,
        action: {}
      ) {
        Text("Delete")
          .frame(width: 6, height: 1, alignment: .center)
      }
      .id(testIdentity("PlainDeleteButton"))
      .buttonStyle(.plain),
      context: .init(
        identity: testIdentity("PlainRoot"),
        environmentValues: environmentValues
      )
    )

    #expect(artifacts.resolvedTree.kind == .view("Button"))
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("DeleteButton")])
    #expect(actionRegistry.dispatch(identity: testIdentity("DeleteButton")))
    #expect(tapBox.didTap)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Delete"))
    #expect(plainArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Delete"))
    #expect(artifacts.rasterSurface != plainArtifacts.rasterSurface)
  }

  @Test("plain Button removes chrome while preserving role-aware foreground semantics")
  func plainButtonRemovesChrome() {
    final class TapBox {
      var didTap = false
    }
    let tapBox = TapBox()
    let actionRegistry = LocalActionRegistry()
    let artifacts = DefaultRenderer().render(
      Button("Delete", role: .destructive) {
        tapBox.didTap = true
      }
      .id(testIdentity("DeleteButton"))
      .buttonStyle(.plain),
      context: .init(
        identity: testIdentity("Plain"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.rasterSurface.lines == ["Delete"])
    #expect(actionRegistry.dispatch(identity: testIdentity("DeleteButton")))
    #expect(tapBox.didTap)
  }

  @Test("link Button lowers to link-colored underlined text without border chrome")
  func linkButtonUsesInlineLinkChrome() {
    var environmentValues = EnvironmentValues()
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    environmentValues.terminalAppearance = appearance

    let theme = appearance.synthesizedTheme()
    let expectedLinkColor = theme.link
    final class TapBox {
      var didTap = false
    }
    let tapBox = TapBox()
    let actionRegistry = LocalActionRegistry()

    let artifacts = DefaultRenderer().render(
      Button("Docs") {
        tapBox.didTap = true
      }
      .id(testIdentity("DocsButton"))
      .buttonStyle(.link),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.rasterSurface.lines == ["Docs"])
    #expect(actionRegistry.dispatch(identity: testIdentity("DocsButton")))
    #expect(tapBox.didTap)
    #expect(
      artifacts.rasterSurface.styleRuns == [
        RasterStyleRun(
          x: 0,
          y: 0,
          length: 4,
          style: ResolvedTextStyle(
            foregroundColor: expectedLinkColor,
            backgroundColor: .white,
            emphasis: [],
            underlineStyle: .init(pattern: .solid),
            strikethroughStyle: nil,
            opacity: 1
          )
        )
      ])
  }

  @Test("Link resolves as focusable rich text and dispatches open-link actions")
  func linkResolvesAsFocusableRichText() {
    final class OpenLinkRecorder: Sendable {
      private let destinationsStorage = LockedBox<[LinkDestination]>([])

      var destinations: [LinkDestination] {
        destinationsStorage.value
      }

      func record(_ destination: LinkDestination) {
        destinationsStorage.withLock { $0.append(destination) }
      }
    }

    let recorder = OpenLinkRecorder()
    let actionRegistry = LocalActionRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.openLinkAction = OpenLinkAction { destination in
      recorder.record(destination)
      return true
    }

    let artifacts = DefaultRenderer().render(
      Link("Docs", destination: "https://example.com")
        .id(testIdentity("DocsLink")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.resolvedTree.kind == .view("Link"))
    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity) == [testIdentity("DocsLink")])

    guard case .richText(let payload) = artifacts.resolvedTree.drawPayload else {
      Issue.record("Expected Link to resolve to a rich text payload")
      return
    }

    #expect(payload.visibleText == "Docs")
    #expect(payload.runs.compactMap(\.destination) == ["https://example.com"])
    #expect(actionRegistry.dispatch(identity: testIdentity("DocsLink")))
    #expect(recorder.destinations == ["https://example.com"])
  }

  @Test("Text interpolation keeps inline links in one rich text payload and separate focus targets")
  func textInterpolationBuildsRichLinkPayload() {
    let artifacts = DefaultRenderer().render(
      Text(
        "See \(Text("v1").bold()) \(Link("Docs", destination: "https://example.com")) or \(Link("API", destination: "https://example.org"))"
      ),
      context: .init(identity: testIdentity("InlineText"))
    )

    guard case .richText(let payload) = artifacts.resolvedTree.drawPayload else {
      Issue.record("Expected interpolated Text to resolve to a rich text payload")
      return
    }

    #expect(payload.visibleText == "See v1 Docs or API")
    #expect(payload.runs.map(\.text) == ["See ", "v1", " ", "Docs", " or ", "API"])
    #expect(payload.runs[1].style.emphasis.contains(.bold))
    #expect(payload.runs[3].destination?.rawValue == "https://example.com")
    #expect(payload.runs[3].linkIdentifier == "InlineLink[0]")
    #expect(payload.runs[5].destination?.rawValue == "https://example.org")
    #expect(payload.runs[5].linkIdentifier == "InlineLink[1]")
    #expect(
      artifacts.semanticSnapshot.focusRegions.map(\.identity) == [
        testIdentity("InlineText", "InlineLink[0]"),
        testIdentity("InlineText", "InlineLink[1]"),
      ]
    )
  }

  @Test("focused standalone and inline links use highlighted link chrome")
  func focusedLinksUseHighlightedChrome() throws {
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )

    var standaloneEnvironment = EnvironmentValues()
    standaloneEnvironment.terminalAppearance = appearance
    standaloneEnvironment.focusedIdentity = testIdentity("DocsLink")
    let standaloneArtifacts = DefaultRenderer().render(
      Link("Docs", destination: "https://example.com")
        .id(testIdentity("DocsLink")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: standaloneEnvironment
      )
    )
    let standaloneStyle = try #require(standaloneArtifacts.rasterSurface.styleRuns.first?.style)
    #expect(standaloneStyle.underlineStyle == .init(pattern: .solid))
    #expect(standaloneStyle.backgroundColor != nil)

    var inlineEnvironment = EnvironmentValues()
    inlineEnvironment.terminalAppearance = appearance
    inlineEnvironment.focusedIdentity = inlineLinkIdentity(
      parent: testIdentity("InlineFocused"),
      identifier: "InlineLink[0]"
    )
    let inlineArtifacts = DefaultRenderer().render(
      Text("Go \(Link("Docs", destination: "https://example.com"))"),
      context: .init(
        identity: testIdentity("InlineFocused"),
        environmentValues: inlineEnvironment
      )
    )
    let inlineStyle = try #require(inlineArtifacts.rasterSurface.styleRuns.last?.style)
    #expect(inlineStyle.underlineStyle == .init(pattern: .solid))
    #expect(inlineStyle.backgroundColor != nil)
  }

  @Test("automatic and prominent buttons stay dense single-line controls by default")
  func automaticAndProminentButtonsStayDenseByDefault() {
    let standardArtifacts = DefaultRenderer().render(
      Button("OK") {},
      context: .init(identity: testIdentity("Standard"))
    )
    let increasedArtifacts = DefaultRenderer().render(
      Button("OK") {}
        .buttonStyle(.borderedProminent),
      context: .init(identity: testIdentity("Increased"))
    )

    #expect(standardArtifacts.rasterSurface.lines.count == 1)
    #expect(increasedArtifacts.rasterSurface.lines.count == 1)
    #expect(standardArtifacts.rasterSurface.lines[0].contains("OK"))
    #expect(increasedArtifacts.rasterSurface.lines[0].contains("OK"))
  }

  @Test("focused standard Button uses outline-first chrome instead of a filled border ring")
  func focusedStandardButtonUsesOutlineFirstChrome() {
    var environmentValues = EnvironmentValues()
    let appearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    environmentValues.terminalAppearance = appearance
    environmentValues.focusedIdentity = testIdentity("OutlineButton")

    let artifacts = DefaultRenderer().render(
      Button("OK") {}
        .id(testIdentity("OutlineButton"))
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "┏━━┓",
        "┃OK┃",
        "┗━━┛",
      ])
    #expect(artifacts.rasterSurface.cells[0][0].style?.backgroundColor == nil)
    #expect(artifacts.rasterSurface.cells[1][1].style?.backgroundColor != nil)
  }

  @Test("focused prominent Button uses a distinct border ring from the idle state")
  func focusedProminentButtonUsesDistinctBorderChrome() {
    var environmentValues = EnvironmentValues()
    let appearance = TerminalAppearance(
      foregroundColor: .white,
      backgroundColor: hexColor("#2D2A2E"),
      tintColor: hexColor("#FC9867"),
      source: .override
    )
    environmentValues.terminalAppearance = appearance

    let idleArtifacts = DefaultRenderer().render(
      Button("OK") {}
        .id(testIdentity("ProminentButton"))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    environmentValues.focusedIdentity = testIdentity("ProminentButton")
    let focusedArtifacts = DefaultRenderer().render(
      Button("OK") {}
        .id(testIdentity("ProminentButton"))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    #expect(idleArtifacts.rasterSurface.lines == focusedArtifacts.rasterSurface.lines)
    #expect(idleArtifacts.rasterSurface != focusedArtifacts.rasterSurface)
  }

  @Test("pressed Button renders a distinct activated chrome state")
  func pressedButtonUsesActivatedChrome() {
    var focusedEnvironment = EnvironmentValues()
    focusedEnvironment.focusedIdentity = testIdentity("PressableButton")
    let focusedArtifacts = DefaultRenderer().render(
      Button("OK") {}
        .id(testIdentity("PressableButton")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: focusedEnvironment
      )
    )

    var pressedEnvironment = focusedEnvironment
    pressedEnvironment.pressedIdentity = testIdentity("PressableButton")
    let pressedArtifacts = DefaultRenderer().render(
      Button("OK") {}
        .id(testIdentity("PressableButton")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: pressedEnvironment
      )
    )

    #expect(focusedArtifacts.rasterSurface.lines == pressedArtifacts.rasterSurface.lines)
    #expect(focusedArtifacts.rasterSurface != pressedArtifacts.rasterSurface)
  }

  @Test("focused Toggle uses a rail highlight without obscuring its label")
  func focusedToggleUsesRailHighlight() {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("AccentToggle")

    let artifacts = DefaultRenderer().render(
      Toggle("Accent Preview", isOn: .constant(false))
        .id(testIdentity("AccentToggle")),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("▌ ○ Accent Preview"))
    #expect(!surface.contains("╭"))
    #expect(!surface.contains("╰"))
  }

  @Test("ControlGroup lays out grouped controls and labeled groups stack their label above content")
  func controlGroupRendersGroupedControls() {
    let unlabeledArtifacts = DefaultRenderer().render(
      ControlGroup {
        Button("A") {}
          .buttonStyle(.plain)
        Button("B") {}
          .buttonStyle(.plain)
      },
      context: .init(identity: testIdentity("ControlGroup"))
    )
    let labeledArtifacts = DefaultRenderer().render(
      ControlGroup("Actions") {
        Button("A") {}
          .buttonStyle(.plain)
        Button("B") {}
          .buttonStyle(.plain)
      },
      context: .init(identity: testIdentity("LabeledControlGroup"))
    )

    #expect(unlabeledArtifacts.rasterSurface.lines == ["A B"])
    #expect(
      labeledArtifacts.rasterSurface.lines == [
        "Actions",
        "A B",
      ])
  }

  @Test("button rows do not bleed their bottom border into the next stacked row")
  func buttonRowsDoNotBleedIntoFollowingRows() throws {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        ControlGroup {
          Button("+1", action: {})
            .buttonStyle(.borderedProminent)
          Button("-1", action: {})
            .buttonStyle(.bordered)
          Button("Reset", action: {})
            .buttonStyle(.borderedProminent)
        }
        .buttonBorderShape(.roundedRectangle)
        .frame(width: 40, height: 3, alignment: .leading)
        EmptyView()
          .frame(width: 40, height: 1, alignment: .leading)
        Toggle("Accent Preview", isOn: .constant(false))
          .frame(width: 40, height: 1, alignment: .leading)
      },
      context: .init(identity: testIdentity("ButtonBleed"))
    )

    let accentLine = try #require(
      artifacts.rasterSurface.lines.first(where: { $0.contains("Accent Preview") })
    )

    #expect(!accentLine.contains("╯"))
    #expect(!accentLine.contains("╰"))
  }

  @Test("GroupBox renders labeled container chrome around its content")
  func groupBoxRendersLabeledContainer() {
    let artifacts = DefaultRenderer().render(
      GroupBox("Panel") {
        VStack(alignment: .leading, spacing: 0) {
          Text("One").frame(width: 4, height: 1, alignment: .leading)
          Text("Two").frame(width: 4, height: 1, alignment: .leading)
        }
      },
      context: .init(identity: testIdentity("GroupBox"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "Panel",
        "╭────╮",
        "│One │",
        "│Two │",
        "╰────╯",
      ])
    #expect(artifacts.rasterSurface.cells[1][0].style?.backgroundColor == nil)
  }

  @Test("GroupBox stacks multiple direct content children vertically")
  func groupBoxStacksDirectContentChildren() {
    let artifacts = DefaultRenderer().render(
      GroupBox("Panel") {
        Text("One")
        Text("Two")
      },
      context: .init(identity: testIdentity("GroupBoxDirectChildren"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "Panel",
        "╭───╮",
        "│One│",
        "│Two│",
        "╰───╯",
      ])
  }

  @Test("ProgressView, Meter, and Sparkline render compact metrics displays")
  func metricsDisplaysRenderCompactTracksAndTrendGlyphs() {
    let progressArtifacts = DefaultRenderer().render(
      ProgressView("Load", value: 3, total: 4, barWidth: 8),
      context: .init(identity: testIdentity("ProgressDisplay"))
    )
    let meterArtifacts = DefaultRenderer().render(
      Meter("Health", value: 7, total: 10, tone: .success, barWidth: 8),
      context: .init(identity: testIdentity("MeterDisplay"))
    )
    let sparklineArtifacts = DefaultRenderer().render(
      Sparkline("Trend", values: [1, 3, 2, 5, 8], tone: .warning),
      context: .init(identity: testIdentity("SparklineDisplay"))
    )

    let progressSurface = progressArtifacts.rasterSurface.lines.joined(separator: "\n")
    let meterSurface = meterArtifacts.rasterSurface.lines.joined(separator: "\n")
    let sparklineSurface = sparklineArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(progressSurface.contains("Load"))
    #expect(progressSurface.contains("3/4"))
    #expect(progressSurface.contains("█"))
    #expect(meterSurface.contains("Health"))
    #expect(meterSurface.contains("70%"))
    #expect(meterSurface.contains("█"))
    #expect(sparklineSurface.contains("Trend"))
    #expect(sparklineSurface.contains("lo 1 hi 8"))
    #expect(sparklineSurface.contains("▁"))
  }

  @Test("TextEditor renders multiline entry with focused terminal-native chrome")
  func textEditorRendersMultilineEntryWithFocusedChrome() {
    let editorIdentity = testIdentity("TextEditorSurface")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = editorIdentity

    let artifacts = DefaultRenderer().render(
      TextEditor(text: .constant("Line 1\nLine 2"))
        .id(editorIdentity)
        .frame(width: 16, height: 5, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Line 1"))
    #expect(surface.contains("Line 2"))
    #expect(surface.contains("_"))
    #expect(artifacts.semanticSnapshot.focusRegions.map(\.identity).contains(editorIdentity))
  }

  @Test("indeterminate ProgressView renders a compact loading track without a summary")
  func indeterminateProgressViewRendersCompactLoadingTrack() {
    let artifacts = DefaultRenderer().render(
      ProgressView("Syncing", barWidth: 8),
      context: .init(identity: testIdentity("IndeterminateProgress"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Syncing"))
    #expect(surface.contains("█"))
    #expect(surface.contains("─"))
    #expect(!surface.contains("/"))
  }

  @Test("alert and confirmationDialog render terminal-native presentation surfaces")
  func presentationModifiersRenderTerminalNativePrompts() {
    let alertSurface = DefaultRenderer().render(
      Text("Workspace")
        .alert(
          "Delete project",
          isPresented: .constant(true),
          actions: {
            Button("Delete") {}
            Button("Cancel") {}
          },
          message: {
            Text("This cannot be undone.")
          }
        )
        .frame(width: 32, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("AlertRoot")),
      proposal: .init(width: 32, height: 8)
    ).rasterSurface.lines.joined(separator: "\n")

    let confirmationSurface = DefaultRenderer().render(
      Text("Workspace")
        .confirmationDialog(
          "Archive task",
          isPresented: .constant(true),
          actions: {
            Button("Archive") {}
          },
          message: {
            Text("Move the task out of the active list.")
          }
        )
        .frame(width: 32, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("ConfirmationRoot")),
      proposal: .init(width: 32, height: 8)
    ).rasterSurface.lines.joined(separator: "\n")

    #expect(alertSurface.contains("Delete project"))
    #expect(alertSurface.contains("This cannot be undone."))
    #expect(alertSurface.contains("Delete"))
    #expect(confirmationSurface.contains("Archive task"))
    #expect(confirmationSurface.contains("Archive"))
  }

  @Test("toast auto-dismiss registers a lifecycle task on first render")
  func toastAutoDismissRegistersLifecycleTask() {
    struct ToastTaskProbe: View {
      let terminalSize: Size
      @State private var isPresented = true

      var body: some View {
        Text("Workspace")
          .frame(
            width: terminalSize.width,
            height: terminalSize.height,
            alignment: .topLeading
          )
          .toast(
            "Action performed",
            isPresented: $isPresented,
            style: .success,
            duration: 0.01
          )
      }
    }

    let terminalSize = Size(width: 20, height: 8)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = terminalSize
    let taskRegistry = LocalTaskRegistry()

    let artifacts = DefaultRenderer().render(
      ToastTaskProbe(terminalSize: terminalSize),
      context: .init(
        identity: testIdentity("ToastTaskProbe"),
        environmentValues: environmentValues,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    #expect(
      artifacts.commitPlan.lifecycle.contains(where: { entry in
        guard case .taskStart(let descriptor) = entry.operation else {
          return false
        }
        return taskRegistry.registration(for: entry.identity)?.descriptor == descriptor
      })
    )
    #expect(!taskRegistry.snapshot().isEmpty)
  }

  @Test("Timeline renders a compact sequence of entries")
  func timelineRendersEntryList() {
    let timelineArtifacts = DefaultRenderer().render(
      Timeline([
        .init("Queued", detail: "Awaiting input", tone: .warning),
        .init("Applied", detail: "Value committed", tone: .success),
      ]),
      context: .init(identity: testIdentity("TimelineDisplay"))
    )

    let timelineSurface = timelineArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(timelineSurface.contains("Queued"))
    #expect(timelineSurface.contains("Applied"))
    #expect(timelineSurface.contains("├"))
    #expect(timelineSurface.contains("╰"))
  }

  @Test("Timeline entries without detail collapse to a single row")
  func compactTimelineEntriesDoNotRenderContinuationRows() {
    let artifacts = DefaultRenderer().render(
      Timeline([
        .init("Value 0 | preset 0", tone: .info),
        .init("Mode inspect | tab flow", tone: .warning),
      ]),
      context: .init(identity: testIdentity("CompactTimeline"))
    )

    #expect(artifacts.rasterSurface.lines.count == 2)
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Value 0 | preset 0"))
    #expect(surface.contains("Mode inspect | tab flow"))
    #expect(!surface.contains("│"))
  }

  @Test("BarChart renders labeled bars, summaries, and value text")
  func barChartRendersCompactDashboardBars() {
    let artifacts = DefaultRenderer().render(
      BarChart(
        "Run Stats",
        entries: [
          .init("value", value: 4, tone: .success),
          .init("preset", value: 7, tone: .info),
          .init("delta", value: 2, tone: .warning),
        ],
        barWidth: 8,
        labelWidth: 6
      ),
      context: .init(identity: testIdentity("BarChart"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Run Stats"))
    #expect(surface.contains("max 7"))
    #expect(surface.contains("value"))
    #expect(surface.contains("preset"))
    #expect(surface.contains("delta"))
    #expect(surface.contains("█"))
  }

  @Test("BulletChart renders a filled track with a distinct target marker")
  func bulletChartRendersCurrentVsTargetTrack() {
    let artifacts = DefaultRenderer().render(
      BulletChart(
        "Range",
        value: 4,
        target: 6,
        total: 8,
        tone: .success,
        barWidth: 8
      ),
      context: .init(identity: testIdentity("BulletChart"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Range"))
    #expect(surface.contains("t 6"))
    #expect(surface.contains("█"))
    #expect(surface.contains("◇") || surface.contains("◆"))
  }

  @Test("ComparisonChart renders current tracks against baseline markers")
  func comparisonChartRendersCompactComparisonRows() {
    let artifacts = DefaultRenderer().render(
      ComparisonChart(
        "Run Compare",
        entries: [
          .init("value", current: 4, baseline: 6, total: 8, tone: .warning),
          .init("delta", current: 2, baseline: 0, total: 8, tone: .success),
        ],
        barWidth: 8,
        labelWidth: 6
      ),
      context: .init(identity: testIdentity("ComparisonChart"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Run Compare"))
    #expect(surface.contains("max 8"))
    #expect(surface.contains("value"))
    #expect(surface.contains("4/6"))
    #expect(surface.contains("◆") || surface.contains("◇"))
  }

  @Test("ThresholdGauge renders banded tracks with a positioned marker")
  func thresholdGaugeRendersCompactBands() {
    let artifacts = DefaultRenderer().render(
      ThresholdGauge(
        "Preset Sync",
        value: 6,
        total: 10,
        bands: [
          .init(upTo: 3, tone: .warning),
          .init(upTo: 7, tone: .info),
          .init(upTo: 10, tone: .success),
        ],
        barWidth: 8
      ),
      context: .init(identity: testIdentity("ThresholdGauge"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Preset Sync"))
    #expect(surface.contains("6/10"))
    #expect(surface.contains("◆"))
    #expect(surface.contains("━"))
  }

  @Test("ColumnChart renders stacked rows plus a compact label strip")
  func columnChartRendersCompactVerticalBars() {
    let artifacts = DefaultRenderer().render(
      ColumnChart(
        "Preset Flow",
        entries: [
          .init("-3", value: 3, tone: .warning),
          .init("0", value: 0, tone: .info),
          .init("7", value: 7, tone: .success),
        ],
        chartHeight: 4,
        columnWidth: 2
      ),
      context: .init(identity: testIdentity("ColumnChart"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Preset Flow"))
    #expect(surface.contains("max 7"))
    #expect(surface.contains("-3"))
    #expect(surface.contains("7"))
    #expect(surface.contains("██"))
  }

  @Test("Legend renders tone-aware markers with compact labels")
  func legendRendersCompactToneKeys() {
    let artifacts = DefaultRenderer().render(
      Legend(
        items: [
          .init("live", tone: .success),
          .init("preset", tone: .info),
          .init("delta", tone: .warning),
        ],
        itemSpacing: 1
      ),
      context: .init(identity: testIdentity("Legend"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("■"))
    #expect(surface.contains("live"))
    #expect(surface.contains("preset"))
    #expect(surface.contains("delta"))
  }

  @Test("StackedBarChart renders a proportional multi-tone track")
  func stackedBarChartRendersCompactSegments() {
    let artifacts = DefaultRenderer().render(
      StackedBarChart(
        "Run Stats",
        entries: [
          .init("live", value: 4, tone: .success),
          .init("preset", value: 2, tone: .info),
          .init("delta", value: 1, tone: .warning),
        ],
        barWidth: 8
      ),
      context: .init(identity: testIdentity("StackedBarChart"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Run Stats"))
    #expect(surface.contains("sum 7"))
    #expect(surface.contains("█"))
  }

  @Test("HeatStrip renders intensity cells plus a compact label row")
  func heatStripRendersCompactIntensityRow() {
    let artifacts = DefaultRenderer().render(
      HeatStrip(
        "Preset Flow",
        entries: [
          .init("-3", value: 3, tone: .warning),
          .init("0", value: 0, tone: .info),
          .init("7", value: 7, tone: .success),
        ],
        cellWidth: 2
      ),
      context: .init(identity: testIdentity("HeatStrip"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Preset Flow"))
    #expect(surface.contains("hi 7"))
    #expect(surface.contains("-3"))
    #expect(surface.contains("7"))
    #expect(surface.contains("▒") || surface.contains("▓") || surface.contains("█"))
  }

  @Test("Text measures and rasterizes explicit newlines as multiline content")
  func textSupportsExplicitNewlines() {
    let artifacts = DefaultRenderer().render(
      Text("Hi\nThere"),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 5, height: 2))
    #expect(artifacts.rasterSurface.lines == ["Hi", "There"])
  }

  @Test("Text wraps to the finite proposed width without rendering first")
  func textWrapsUnderFiniteWidthProposals() {
    let artifacts = DefaultRenderer().render(
      Text("ABCDEFG"),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 3, height: nil)
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 3, height: 5))
    #expect(artifacts.rasterSurface.lines == ["AB–", "–C–", "–D–", "–E–", "–FG"])
  }

  @Test("Text prefers word-boundary wrapping in measurement, draw extraction, and rasterization")
  func textUsesWordBoundaryWrappingAcrossPipeline() {
    let artifacts = DefaultRenderer().render(
      Text("alpha beta gamma")
        .textWrappingStrategy(.wordBoundary),
      context: .init(identity: testIdentity("WordBoundary")),
      proposal: .init(width: 6, height: nil)
    )

    #expect(artifacts.resolvedTree.layoutMetadata.textWrappingStrategy == .wordBoundary)
    #expect(artifacts.measuredTree.measuredSize == .init(width: 5, height: 3))
    #expect(artifacts.rasterSurface.lines == ["alpha", "beta", "gamma"])

    guard let firstCommand = artifacts.drawTree.commands.first else {
      Issue.record("Expected a text draw command on the wrapped root")
      return
    }
    guard case .text(_, _, _, _, _, let wrappingStrategy) = firstCommand else {
      Issue.record("Expected a text draw command on the wrapped root")
      return
    }

    #expect(wrappingStrategy == .wordBoundary)
  }

  @Test("Text measures terminal cell widths for wide glyphs and combining marks")
  func textMeasuresTerminalCellWidths() {
    let wideArtifacts = DefaultRenderer().render(
      Text("界A"),
      context: .init(identity: testIdentity("Wide")),
      proposal: .init(width: 2, height: nil)
    )
    let combiningArtifacts = DefaultRenderer().render(
      Text("e\u{301}A"),
      context: .init(identity: testIdentity("Combining"))
    )

    #expect(wideArtifacts.measuredTree.measuredSize == .init(width: 2, height: 2))
    #expect(wideArtifacts.rasterSurface.lines == ["界", "A"])

    #expect(combiningArtifacts.measuredTree.measuredSize == .init(width: 2, height: 1))
    #expect(combiningArtifacts.rasterSurface.lines == ["e\u{301}A"])
  }

  @Test("lineLimit and truncationMode shape the visible text layout")
  func lineLimitAndTruncationShapeVisibleText() {
    let tailArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .lineLimit(1),
      context: .init(identity: testIdentity("Tail")),
      proposal: .init(width: 4, height: nil)
    )
    let headArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .lineLimit(1)
        .truncationMode(.head),
      context: .init(identity: testIdentity("Head")),
      proposal: .init(width: 4, height: nil)
    )
    let middleArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .lineLimit(1)
        .truncationMode(.middle),
      context: .init(identity: testIdentity("Middle")),
      proposal: .init(width: 4, height: nil)
    )
    let multilineArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .lineLimit(2),
      context: .init(identity: testIdentity("Multiline")),
      proposal: .init(width: 3, height: nil)
    )

    #expect(tailArtifacts.measuredTree.measuredSize == .init(width: 4, height: 1))
    #expect(tailArtifacts.rasterSurface.lines == ["ABC…"])
    #expect(headArtifacts.rasterSurface.lines == ["…BC–"])
    #expect(middleArtifacts.rasterSurface.lines == ["A…C–"])
    #expect(multilineArtifacts.measuredTree.measuredSize == .init(width: 3, height: 2))
    #expect(multilineArtifacts.rasterSurface.lines == ["AB–", "–C…"])
  }

  @Test("rich Text wrapping and truncation treat inline links as one text layout")
  func richTextWrappingAndTruncationTreatLinksAsSingleLayout() throws {
    let artifacts = DefaultRenderer().render(
      Text("Alpha \(Link("Beta", destination: "https://example.com")) Gamma")
        .lineLimit(2)
        .textWrappingStrategy(.wordBoundary),
      context: .init(identity: testIdentity("RichWrap")),
      proposal: .init(width: 5, height: nil)
    )

    guard case .richText(let payload) = artifacts.resolvedTree.drawPayload else {
      Issue.record("Expected wrapped rich Text to resolve to a rich text payload")
      return
    }

    #expect(payload.visibleText == "Alpha Beta Gamma")
    #expect(artifacts.measuredTree.measuredSize == .init(width: 5, height: 2))
    #expect(artifacts.rasterSurface.lines == ["Alpha", "Beta…"])

    let focusRegion = try #require(artifacts.semanticSnapshot.focusRegions.first)
    #expect(focusRegion.identity == testIdentity("RichWrap", "InlineLink[0]"))
    #expect(
      focusRegion.rect
        == Rect(
          origin: .init(x: 0, y: 1),
          size: .init(width: 4, height: 1)
        )
    )
  }

  @Test("multiline Text exposes distinct first and last baselines")
  func multilineTextBaselinesParticipateInAlignment() {
    let firstBaselineArtifacts = DefaultRenderer().render(
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("A\nB")
        Text("C")
      },
      context: .init(identity: testIdentity("First"))
    )
    let lastBaselineArtifacts = DefaultRenderer().render(
      HStack(alignment: .lastTextBaseline, spacing: 0) {
        Text("A\nB")
        Text("C")
      },
      context: .init(identity: testIdentity("Last"))
    )

    #expect(
      firstBaselineArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 0),
      ])
    #expect(firstBaselineArtifacts.rasterSurface.lines == ["AC", "B"])

    #expect(
      lastBaselineArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 1),
      ])
    #expect(lastBaselineArtifacts.rasterSurface.lines == ["A", "BC"])
  }

  @Test("padding and frame preserve text baselines through wrapper propagation")
  func wrapperPropagationPreservesTextBaselines() {
    let paddedArtifacts = DefaultRenderer().render(
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("A").padding(.init(top: 1, leading: 0, bottom: 1, trailing: 0))
        Text("B")
      },
      context: .init(identity: testIdentity("Padded"))
    )
    let framedArtifacts = DefaultRenderer().render(
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("A").frame(width: 1, height: 3, alignment: .bottomLeading)
        Text("B")
      },
      context: .init(identity: testIdentity("Framed"))
    )

    #expect(paddedArtifacts.measuredTree.measuredSize == .init(width: 2, height: 3))
    #expect(
      paddedArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 1),
      ])
    #expect(paddedArtifacts.rasterSurface.lines == ["", "AB", ""])

    #expect(framedArtifacts.measuredTree.measuredSize == .init(width: 2, height: 3))
    #expect(
      framedArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 2),
      ])
    #expect(framedArtifacts.rasterSurface.lines == ["", "", "AB"])
  }

  @Test("offset is layout-neutral and moves rendered output")
  func offsetMovesRenderedOutputWithoutChangingWrapperLayout() {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .offset(.init(width: 2, height: 1))
        .frame(width: 5, height: 3, alignment: .topLeading),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 5, height: 3))
    #expect(artifacts.placedTree.kind == .view("Frame"))
    #expect(artifacts.placedTree.children.count == 1)
    #expect(artifacts.placedTree.children[0].kind == .view("Offset"))
    #expect(artifacts.placedTree.children[0].bounds.origin == .zero)
    #expect(artifacts.placedTree.children[0].children.map(\.bounds.origin) == [.init(x: 2, y: 1)])
    #expect(artifacts.rasterSurface.lines == ["", "  Hi", ""])
  }

  @Test("offset preserves stack baseline placement while moving the child visually")
  func offsetPreservesStackBaselinePlacement() {
    let artifacts = DefaultRenderer().render(
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("A").offset(x: 0, y: 1)
        Text("B")
      }
      .frame(width: 2, height: 2, alignment: .topLeading),
      context: .init(identity: testIdentity("Root"))
    )

    let stack = artifacts.placedTree.children[0]
    #expect(
      stack.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 0),
      ])
    #expect(stack.children[0].children.map(\.bounds.origin) == [.init(x: 0, y: 1)])
    #expect(artifacts.rasterSurface.lines == [" B", "A"])
  }

  @Test("width-only flexible frames preserve intrinsic height in vertical stacks")
  func widthOnlyFlexibleFramesPreserveIntrinsicHeightInVerticalStacks() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Title")
          Text("Detail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Text("Tail")
      },
      context: .init(identity: testIdentity("FlexibleFrameRoot")),
      proposal: .init(width: 12, height: nil)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.measuredTree.measuredSize == .init(width: 12, height: 3))
    #expect(artifacts.measuredTree.childMeasurements[0].measuredSize == .init(width: 12, height: 2))
    #expect(surface.contains("Title"))
    #expect(surface.contains("Detail"))
    #expect(surface.contains("Tail"))
  }

  @Test("flexible frames absorb extra horizontal slack in horizontal stacks")
  func widthOnlyFlexibleFramesPreserveIntrinsicWidthInHorizontalStacks() {
    // SwiftUI-faithful behaviour: when a rigid `.frame(width:)` sibling
    // leaves slack in an HStack, a `.frame(maxWidth: .infinity)` child
    // absorbs the remaining main-axis room. Without this, a lone
    // "submit"-style cell on a row of fixed-width siblings (the
    // classic calculator `=` key pattern) stays stuck at its minWidth
    // even though its explicit constraint says otherwise.
    let artifacts = DefaultRenderer().render(
      HStack(alignment: .top, spacing: 1) {
        Text("Nav")
          .frame(width: 4, alignment: .leading)

        VStack(alignment: .leading, spacing: 0) {
          Text("Latency")
          Text("Errors")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      },
      context: .init(identity: testIdentity("HorizontalFlexibleFrameRoot")),
      proposal: .init(width: 24, height: nil)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(artifacts.measuredTree.measuredSize == .init(width: 24, height: 2))
    #expect(artifacts.measuredTree.childMeasurements[1].measuredSize.width == 19)
    #expect(surface.contains("Latency"))
    #expect(surface.contains("Errors"))
  }

  @Test("Divider expands across the stack minor axis under finite proposals")
  func dividerExpandsAcrossMinorAxis() {
    let verticalArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("A")
        Divider()
        Text("B")
      },
      context: .init(identity: testIdentity("Vertical")),
      proposal: .init(width: 4, height: nil)
    )
    let horizontalArtifacts = DefaultRenderer().render(
      HStack(alignment: .top, spacing: 0) {
        Text("A")
        Divider()
        Text("B")
      },
      context: .init(identity: testIdentity("Horizontal")),
      proposal: .init(width: nil, height: 3)
    )

    #expect(verticalArtifacts.measuredTree.measuredSize == .init(width: 4, height: 3))
    #expect(verticalArtifacts.rasterSurface.lines == ["A", "────", "B"])

    #expect(horizontalArtifacts.measuredTree.measuredSize == .init(width: 3, height: 3))
    #expect(horizontalArtifacts.rasterSurface.lines == ["A│B", " │", " │"])
  }

  @Test("Divider keeps the enclosing stack direction when framed")
  func dividerKeepsStackDrivenOrientationWhenFramed() {
    let verticalArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("A")
        Divider().frame(width: 3, height: 4)
        Text("B")
      },
      context: .init(identity: testIdentity("VerticalFramed"))
    )
    let horizontalArtifacts = DefaultRenderer().render(
      HStack(alignment: .top, spacing: 0) {
        Text("A")
        Divider().frame(width: 4, height: 3)
        Text("B")
      },
      context: .init(identity: testIdentity("HorizontalFramed"))
    )

    #expect(verticalArtifacts.measuredTree.measuredSize == .init(width: 3, height: 6))
    #expect(verticalArtifacts.rasterSurface.lines == ["A", "", "───", "", "", "B"])

    #expect(horizontalArtifacts.measuredTree.measuredSize == .init(width: 6, height: 3))
    #expect(horizontalArtifacts.rasterSurface.lines == ["A │  B", "  │", "  │"])
  }

  @Test("Divider inherits stack direction through lazy indexed child sources")
  func dividerInLazyIndexedChildSourceUsesStackDirection() {
    let artifacts = DefaultRenderer().render(
      LazyHStack(alignment: .top, spacing: 0) {
        ForEach([0, 1, 2], id: \.self) { index in
          if index == 0 {
            Text("A")
          } else if index == 1 {
            Divider().frame(width: 4, height: 3)
          } else {
            Text("B")
          }
        }
      },
      context: .init(identity: testIdentity("LazyHorizontalFramed"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 6, height: 3))
    #expect(artifacts.rasterSurface.lines == ["A │  B", "  │", "  │"])
  }

  @Test("border and divider styles lower through richer raster families")
  func borderAndRuleStylesLowerThroughRasterFamilies() {
    let borderArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          RoundedRectangle(cornerRadius: 1)
            .stroke(.separator, style: .init(borderSet: .rounded))
        },
      context: .init(identity: testIdentity("Border"))
    )
    let ruleArtifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Divider(
          drawMetadata: .init(
            borderStrokeStyle: .init(borderSet: .heavy)
          )
        )
      },
      context: .init(identity: testIdentity("Rule")),
      proposal: .init(width: 4, height: nil)
    )

    #expect(
      borderArtifacts.rasterSurface.lines == [
        "╭──╮",
        "│Hi│",
        "╰──╯",
      ])
    #expect(ruleArtifacts.rasterSurface.lines == ["━━━━"])
  }

  @Test("additional border families lower through the shared BorderSet model")
  func additionalBorderFamiliesLowerThroughSharedBorderSetModel() {
    let blockArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .block))
        },
      context: .init(identity: testIdentity("Block"))
    )
    let outerHalfBlockArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .outerHalfBlock))
        },
      context: .init(identity: testIdentity("OuterHalfBlock"))
    )
    let innerHalfBlockArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .innerHalfBlock))
        },
      context: .init(identity: testIdentity("InnerHalfBlock"))
    )
    let presentationChromeArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .presentationChrome))
        },
      context: .init(identity: testIdentity("PresentationChrome"))
    )
    let hiddenArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .hidden))
        },
      context: .init(identity: testIdentity("Hidden"))
    )
    let markdownArtifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: .init(borderSet: .markdown))
        },
      context: .init(identity: testIdentity("Markdown"))
    )

    #expect(
      blockArtifacts.rasterSurface.lines == [
        "████",
        "█Hi█",
        "████",
      ])
    #expect(
      outerHalfBlockArtifacts.rasterSurface.lines == [
        "▛▀▀▜",
        "▌Hi▐",
        "▙▄▄▟",
      ])
    #expect(
      innerHalfBlockArtifacts.rasterSurface.lines == [
        "▗▄▄▖",
        "▐Hi▌",
        "▝▀▀▘",
      ])
    #expect(
      presentationChromeArtifacts.rasterSurface.lines == [
        "▗▄▄▖",
        "▐Hi▌",
        "▝▀▀▘",
      ])
    #expect(
      hiddenArtifacts.rasterSurface.lines == [
        "    ",
        " Hi ",
        "    ",
      ])
    #expect(hiddenArtifacts.rasterSurface.cells[0][0].style != nil)
    #expect(
      markdownArtifacts.rasterSurface.lines == [
        "|--|",
        "|Hi|",
        "|--|",
      ])
  }

  @Test(
    "StrokeStyle exposes lipgloss border presets with the expected glyph families",
    arguments: [
      (StrokeStyle.normal, ["┌──┐", "│Hi│", "└──┘"]),
      (StrokeStyle.rounded, ["╭──╮", "│Hi│", "╰──╯"]),
      (StrokeStyle.thick, ["┏━━┓", "┃Hi┃", "┗━━┛"]),
      (StrokeStyle.double, ["╔══╗", "║Hi║", "╚══╝"]),
      (StrokeStyle.ascii, ["+--+", "|Hi|", "+--+"]),
      (StrokeStyle.block, ["████", "█Hi█", "████"]),
      (StrokeStyle.outerHalfBlock, ["▛▀▀▜", "▌Hi▐", "▙▄▄▟"]),
      (StrokeStyle.innerHalfBlock, ["▗▄▄▖", "▐Hi▌", "▝▀▀▘"]),
      (StrokeStyle.hidden, ["    ", " Hi ", "    "]),
      (StrokeStyle.markdown, ["|--|", "|Hi|", "|--|"]),
    ]
  )
  func strokeStylePresetsMatchLipGlossBorderFamilies(
    style: StrokeStyle,
    expected: [String]
  ) {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .padding(1)
        .overlay {
          Rectangle()
            .stroke(.separator, style: style)
        },
      context: .init(identity: testIdentity("LipGlossBorderFamily"))
    )

    #expect(artifacts.rasterSurface.lines == expected)
  }

  @Test("text styling survives draw extraction and raster style runs")
  func textStylingSurvivesDrawAndRaster() {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .bold()
        .foregroundStyle(.tint)
        .lineLimit(1)
        .textWrappingStrategy(.wordBoundary)
        .drawMetadata(.init(opacity: 0.5)),
      context: .init(identity: testIdentity("Styled"))
    )

    #expect(artifacts.resolvedTree.layoutMetadata.lineLimit == 1)
    #expect(artifacts.resolvedTree.layoutMetadata.textTruncationMode == nil)
    #expect(artifacts.resolvedTree.layoutMetadata.textWrappingStrategy == .wordBoundary)

    guard let firstCommand = artifacts.drawTree.commands.first else {
      Issue.record("Expected a draw command on the styled root")
      return
    }
    guard
      case .text(
        let bounds,
        let content,
        let style,
        let lineLimit,
        let truncationMode,
        let wrappingStrategy
      ) =
        firstCommand
    else {
      Issue.record("Expected a text draw command on the styled root")
      return
    }

    #expect(
      bounds == Rect(origin: Point.zero, size: Size(width: 2, height: 1)))
    #expect(content == "Hi")
    #expect(
      style
        == TextStyle(
          foregroundStyle: AnyShapeStyle.semantic(.tint),
          emphasis: .bold,
          opacity: 0.5
        ))
    #expect(lineLimit == 1)
    #expect(truncationMode == .tail)
    #expect(wrappingStrategy == .wordBoundary)
    // The raster surface bakes fractional opacity into the foreground
    // color so terminals see smooth intermediate shades instead of a
    // binary SGR "faint".  The emphasis and geometry still flow through
    // untouched; the style-run's opacity is normalized to 1.0 and the
    // foreground color is no longer the raw semantic(.tint) sentinel.
    #expect(artifacts.rasterSurface.styleRuns.count == 1)
    guard let rasterRun = artifacts.rasterSurface.styleRuns.first else {
      Issue.record("Expected one style run on the styled text raster")
      return
    }
    #expect(rasterRun.x == 0)
    #expect(rasterRun.y == 0)
    #expect(rasterRun.length == 2)
    #expect(rasterRun.style.emphasis == .bold)
    #expect(rasterRun.style.opacity == 1.0)
    #expect(rasterRun.style.foregroundColor != nil)
  }

  @Test("text emphasis and decoration modifiers map into typed draw metadata")
  func textEmphasisAndDecorationModifiersMapIntoTypedDrawMetadata() {
    let resolved = Resolver().resolve(
      Text("Emphasis")
        .bold()
        .italic()
        .underline(pattern: .dash, color: .yellow)
        .strikethrough(false),
      in: .init(identity: testIdentity("Text"))
    )

    #expect(resolved.drawMetadata.emphasis == [.bold, .italic])
    #expect(resolved.drawMetadata.underlineStyle == .init(pattern: .dash, color: .yellow))
    #expect(resolved.drawMetadata.strikethroughStyle == nil)
  }

  @Test("additional inline emphasis and underline variants map into typed draw metadata")
  func additionalInlineTextStylesMapIntoTypedDrawMetadata() {
    let resolved = Resolver().resolve(
      Text("Inline")
        .faint()
        .blink()
        .reverse()
        .underline(pattern: .curly, color: .yellow)
        .strikethrough(pattern: .double, color: .red),
      in: .init(identity: testIdentity("Text"))
    )

    #expect(resolved.drawMetadata.emphasis == [.faint, .blink, .reverse])
    #expect(resolved.drawMetadata.underlineStyle == .init(pattern: .curly, color: .yellow))
    #expect(resolved.drawMetadata.strikethroughStyle == .init(pattern: .double, color: .red))
  }

  @Test("gradient stop convenience APIs preserve typed linear gradients")
  func gradientStopConveniencesPreserveTypedLinearGradients() {
    let gradient = LinearGradient(
      stops: [
        .init(color: .red, location: 0),
        .init(color: .blue, location: 1),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
    let artifacts = DefaultRenderer().render(
      Text("AB")
        .foregroundStyle(gradient),
      context: .init(identity: testIdentity("Gradient"))
    )

    guard let firstCommand = artifacts.drawTree.commands.first else {
      Issue.record("Expected a draw command on the gradient root")
      return
    }
    guard case .text(_, _, let style, _, _, _) = firstCommand else {
      Issue.record("Expected a text draw command on the gradient root")
      return
    }

    #expect(
      style.foregroundStyle
        == .linearGradient(
          .init(
            gradient: .init(
              stops: [
                .init(color: .red, location: 0),
                .init(color: .blue, location: 1),
              ]
            ),
            startPoint: .leading,
            endPoint: .trailing
          )
        ))
    #expect(artifacts.rasterSurface.styleRuns.count == 2)
    #expect(
      artifacts.rasterSurface.styleRuns[0].style.foregroundColor
        != artifacts.rasterSurface.styleRuns[1].style.foregroundColor)
  }

  @Test("tile background renders tiled content with framework styles")
  func tileBackgroundRendersTiledContent() {
    let artifacts = DefaultRenderer().render(
      TileBackground(
        width: 6,
        height: 2,
        tiles: ["xo"],
        style: .terminalTile(.info)
      ),
      context: .init(identity: testIdentity("TileBackground"))
    )

    #expect(artifacts.rasterSurface.lines == ["xoxoxo", "xoxoxo"])
    #expect(artifacts.rasterSurface.cells[0][0].style?.foregroundColor != nil)
  }

  @Test("text decoration styling survives draw extraction and raster style runs")
  func textDecorationStylingSurvivesDrawAndRaster() {
    let artifacts = DefaultRenderer().render(
      Text("Hi")
        .underline(pattern: .dashDot, color: .yellow)
        .strikethrough(color: .red),
      context: .init(identity: testIdentity("Decorated"))
    )

    guard let firstCommand = artifacts.drawTree.commands.first else {
      Issue.record("Expected a draw command on the decorated root")
      return
    }
    guard case .text(_, _, let style, _, _, _) = firstCommand else {
      Issue.record("Expected a text draw command on the decorated root")
      return
    }

    #expect(style.underlineStyle == .init(pattern: .dashDot, color: .yellow))
    #expect(style.strikethroughStyle == .init(pattern: .solid, color: .red))
    #expect(
      artifacts.rasterSurface.styleRuns == [
        RasterStyleRun(
          x: 0,
          y: 0,
          length: 2,
          style: ResolvedTextStyle(
            foregroundColor: hexColor("#ECEFF4"),
            backgroundColor: nil,
            emphasis: [],
            underlineStyle: .init(pattern: .dashDot, color: .yellow),
            strikethroughStyle: .init(pattern: .solid, color: .red),
            opacity: 1
          )
        )
      ])
  }

  @Test("clipped hides overflow beyond the current layout bounds")
  func clippedConstrainsRenderedOverflow() {
    let unclippedArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .fixedSize()
        .frame(width: 3, height: 1, alignment: .topLeading),
      context: .init(identity: testIdentity("Unclipped"))
    )
    let clippedArtifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .fixedSize()
        .frame(width: 3, height: 1, alignment: .topLeading)
        .clipped(),
      context: .init(identity: testIdentity("Clipped"))
    )

    #expect(unclippedArtifacts.rasterSurface.lines == ["ABCDEFG"])
    #expect(clippedArtifacts.measuredTree.measuredSize == .init(width: 3, height: 1))
    #expect(clippedArtifacts.rasterSurface.lines == ["ABC"])
  }

  @Test("offset and clipped respect modifier order")
  func offsetAndClippedRespectModifierOrder() {
    let offsetThenClipped = DefaultRenderer().render(
      Text("ABCDEFG")
        .fixedSize()
        .offset(x: 2)
        .frame(width: 5, height: 1, alignment: .leading)
        .clipped()
        .frame(width: 7, height: 1, alignment: .leading),
      context: .init(identity: testIdentity("OffsetThenClipped"))
    )
    let clippedThenOffset = DefaultRenderer().render(
      Text("ABCDEFG")
        .fixedSize()
        .frame(width: 5, height: 1, alignment: .leading)
        .clipped()
        .offset(x: 2)
        .frame(width: 7, height: 1, alignment: .leading),
      context: .init(identity: testIdentity("ClippedThenOffset"))
    )

    #expect(offsetThenClipped.rasterSurface.lines == ["  ABC"])
    #expect(clippedThenOffset.rasterSurface.lines == ["  ABCDE"])
  }

  @Test("fixedSize preserves ideal size along constrained axes")
  func fixedSizePreservesIdealSize() {
    let compressed = DefaultRenderer().render(
      Text("Hello"),
      context: .init(identity: testIdentity("Compressed")),
      proposal: .init(width: 3, height: 1)
    )
    let fixed = DefaultRenderer().render(
      Text("Hello").fixedSize(horizontal: true, vertical: false),
      context: .init(identity: testIdentity("Fixed")),
      proposal: .init(width: 3, height: 1)
    )

    #expect(compressed.measuredTree.measuredSize == .init(width: 3, height: 1))
    #expect(fixed.measuredTree.measuredSize == .init(width: 5, height: 1))
  }

  @Test("explicit frames preserve specified size under tighter proposals")
  func explicitFramesPreserveSpecifiedSizeUnderTightProposals() {
    let artifacts = DefaultRenderer().render(
      Text("BG")
        .bold()
        .padding(1)
        .frame(width: 8, height: 3, alignment: .center)
        .background {
          RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(.fill)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 1)
            .strokeBorder(.separator, background: .warning)
        },
      context: .init(identity: testIdentity("TightFrame")),
      proposal: .init(width: 8, height: 1)
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 8, height: 3))
    #expect(
      artifacts.rasterSurface.lines == [
        "╭──────╮",
        "│  BG  │",
        "╰──────╯",
      ])
  }

  @Test("finite stacks expand Spacer and respect layoutPriority when width is scarce")
  func finiteStacksAllocateMainAxisSpace() {
    let spacerArtifacts = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("A")
        Spacer()
        Text("B")
      },
      context: .init(identity: testIdentity("SpacerRoot")),
      proposal: .init(width: 6, height: 1)
    )
    let priorityArtifacts = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("Wide").layoutPriority(1)
        Text("Text")
      },
      context: .init(identity: testIdentity("PriorityRoot")),
      proposal: .init(width: 6, height: 1)
    )

    #expect(spacerArtifacts.measuredTree.measuredSize == .init(width: 6, height: 1))
    #expect(spacerArtifacts.placedTree.children.map { $0.bounds.size.width } == [1, 4, 1])
    #expect(priorityArtifacts.measuredTree.measuredSize == .init(width: 6, height: 1))
    #expect(priorityArtifacts.placedTree.children.map { $0.bounds.size.width } == [4, 2])
    #expect(priorityArtifacts.rasterSurface.lines == ["WideTe"])
  }

  @Test(
    "finite vertical stacks allow unclipped children to overflow a constrained frame"
  )
  func finiteVerticalStacksAllowOverflowBeyondConstrainedFrame() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        GroupBox("First") {
          Text("alpha")
        }
        GroupBox("Second") {
          Text("beta")
            .frame(width: 4, height: 3, alignment: .center)
        }
      }
      .frame(width: 18, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("ConstrainedPanelStack"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.measuredTree.measuredSize == .init(width: 18, height: 8))
    #expect(artifacts.rasterSurface.lines.count > 8)
    #expect(surface.contains("First"))
    #expect(surface.contains("Second"))
  }

  @Test("constrained vertical stacks keep decorated framed content intact while overflowing")
  @MainActor
  func constrainedVerticalStacksKeepDecoratedFramedContentIntactWhileOverflowing() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        GroupBox("First") {
          Text("alpha")
        }
        GroupBox("Second") {
          Text("BG")
            .bold()
            .padding(1)
            .frame(width: 8, height: 3, alignment: .center)
            .background {
              RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(.fill)
            }
            .overlay {
              RoundedRectangle(cornerRadius: 1)
                .strokeBorder(.separator, background: .warning)
            }
        }
      }
      .frame(width: 18, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("DecoratedOverflowingStack"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.measuredTree.measuredSize == .init(width: 18, height: 8))
    #expect(artifacts.rasterSurface.lines.count > 8)
    #expect(surface.contains("╭──────╮"))
    #expect(surface.contains("│  BG  │"))
    #expect(surface.contains("╰──────╯"))
  }

  @Test("ViewThatFits chooses the first candidate whose ideal width fits")
  func viewThatFitsSelectsTheFirstFittingCandidate() {
    let root = ViewThatFits(in: .horizontal) {
      HStack(spacing: 0) {
        Text("Wide")
        Text("Mode")
      }
      Text("Narrow")
      Text("S")
    }

    let narrowArtifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("NarrowRoot")),
      proposal: .init(width: 5, height: 1)
    )
    let wideArtifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("WideRoot")),
      proposal: .init(width: 10, height: 1)
    )

    #expect(narrowArtifacts.placedTree.children.count == 1)
    #expect(
      narrowArtifacts.placedTree.children[0].identity
        == testIdentity("NarrowRoot", "ViewThatFits[2]"))
    #expect(narrowArtifacts.rasterSurface.lines == ["S"])
    #expect(wideArtifacts.placedTree.children.count == 1)
    #expect(
      wideArtifacts.placedTree.children[0].identity == testIdentity("WideRoot", "ViewThatFits[0]"))
    #expect(wideArtifacts.rasterSurface.lines == ["WideMode"])
  }

  @Test("alignmentGuide overrides feed ViewDimensions and stack placement")
  func alignmentGuideOverridesFeedStackPlacement() {
    let artifacts = DefaultRenderer().render(
      HStack(alignment: .bottom, spacing: 0) {
        Text("A")
          .frame(width: 1, height: 3, alignment: .topLeading)
        Text("B")
          .alignmentGuide(.bottom) { dimensions in
            dimensions[.top]
          }
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 2, height: 4))
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 1, y: 3),
      ])
    #expect(artifacts.rasterSurface.lines == ["A", "", "", " B"])
  }

  @Test("default stack spacing resolves through preferred ViewSpacing when spacing is nil")
  func stackSpacingUsesPreferredSpacingDefaults() {
    let artifacts = DefaultRenderer().render(
      HStack {
        Text("A").layoutMetadata(.init(spacing: .init(horizontal: 2)))
        Text("B")
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 4, height: 1))
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 3, y: 0),
      ])
    #expect(artifacts.rasterSurface.lines == ["A  B"])
  }

  @Test("custom alignment IDs are visible through LayoutSubview dimensions")
  func customAlignmentIDsFlowIntoCustomLayouts() {
    let defaultArtifacts = DefaultRenderer().render(
      RaisedGuideReadingLayout {
        Text("AB")
        Text("C")
      },
      context: .init(identity: testIdentity("Default"))
    )
    let overriddenArtifacts = DefaultRenderer().render(
      RaisedGuideReadingLayout {
        Text("AB").alignmentGuide(.raisedCenter) { dimensions in
          dimensions[.trailing]
        }
        Text("C")
      },
      context: .init(identity: testIdentity("Override"))
    )

    #expect(defaultArtifacts.rasterSurface.lines == ["CB"])
    #expect(overriddenArtifacts.rasterSurface.lines == ["ABC"])
    #expect(
      overriddenArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 2, y: 0),
      ])
  }

  @Test("explicit custom guides survive wrapper propagation into custom layouts")
  func wrapperPropagationPreservesExplicitCustomGuides() {
    let artifacts = DefaultRenderer().render(
      RaisedGuideReadingLayout {
        Text("AB")
          .alignmentGuide(.raisedCenter) { dimensions in
            dimensions[.trailing]
          }
          .padding(1)
        Text("C")
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 4, height: 3))
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 3, y: 0),
      ])
  }

  @Test("ZStack supports arbitrary combined alignment guides")
  func zStackSupportsCombinedAlignmentGuides() {
    let alignment = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    let artifacts = DefaultRenderer().render(
      ZStack(alignment: alignment) {
        Text("AAAA").padding(.init(top: 1, leading: 0, bottom: 0, trailing: 0))
        Text("B")
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 4, height: 2))
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 3, y: 1),
      ])
    #expect(artifacts.rasterSurface.lines == ["", "AAAB"])
  }

  @Test("overlay alignment uses the base view's propagated guides")
  func overlayAlignmentUsesPrimaryGuides() {
    let alignment = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    let artifacts = DefaultRenderer().render(
      Text("AB")
        .padding(.init(top: 1, leading: 0, bottom: 0, trailing: 0))
        .overlay(alignment: alignment) {
          Text("X")
        },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 2, height: 2))
    #expect(artifacts.placedTree.children[1].bounds.origin == .init(x: 1, y: 1))
    #expect(artifacts.rasterSurface.lines == ["", "AX"])
  }

  @Test("ZStackLayout mirrors ZStack combined-alignment placement")
  func zStackLayoutMirrorsZStackPlacement() {
    let alignment = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    let viewArtifacts = DefaultRenderer().render(
      ZStack(alignment: alignment) {
        Text("AAAA").padding(.init(top: 1, leading: 0, bottom: 0, trailing: 0))
        Text("B")
      },
      context: .init(identity: testIdentity("ViewRoot"))
    )
    let layoutArtifacts = DefaultRenderer().render(
      ZStackLayout(alignment: alignment) {
        Text("AAAA").padding(.init(top: 1, leading: 0, bottom: 0, trailing: 0))
        Text("B")
      },
      context: .init(identity: testIdentity("LayoutRoot"))
    )

    #expect(layoutArtifacts.measuredTree.measuredSize == viewArtifacts.measuredTree.measuredSize)
    #expect(
      layoutArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 3, y: 1),
      ])
    #expect(layoutArtifacts.rasterSurface.lines == viewArtifacts.rasterSurface.lines)
  }

  @Test("ForEach expands data-driven children with stable explicit identities")
  func forEachExpandsDataDrivenChildren() {
    let rows = [
      PaletteRow(id: "red", label: "Red"),
      PaletteRow(id: "green", label: "Green"),
      PaletteRow(id: "blue", label: "Blue"),
    ]

    let resolved = Resolver().resolve(
      VStack {
        ForEach(rows) { row in
          Text(row.label)
        }
      },
      in: .init(identity: testIdentity("Root"))
    )

    #expect(
      resolved.children.map(\.identity) == [
        testIdentity("Root", "VStack[0]", "ID[\"red\"]"),
        testIdentity("Root", "VStack[0]", "ID[\"green\"]"),
        testIdentity("Root", "VStack[0]", "ID[\"blue\"]"),
      ])
    #expect(
      resolved.children.map(\.drawPayload) == [
        .text("Red"),
        .text("Green"),
        .text("Blue"),
      ])
  }

  @Test("ForEach keeps explicit child identity stable when data reorders")
  func forEachPreservesIdentityAcrossReorder() {
    let original = [
      PaletteRow(id: "red", label: "Red"),
      PaletteRow(id: "green", label: "Green"),
      PaletteRow(id: "blue", label: "Blue"),
    ]
    let reordered = [
      PaletteRow(id: "blue", label: "Blue"),
      PaletteRow(id: "red", label: "Red"),
      PaletteRow(id: "green", label: "Green"),
    ]

    let makeRoot = { (rows: [PaletteRow]) in
      VStack {
        ForEach(rows) { row in
          Text(row.label)
        }
      }
    }

    let originalResolved = Resolver().resolve(
      makeRoot(original), in: .init(identity: testIdentity("Root")))
    let reorderedResolved = Resolver().resolve(
      makeRoot(reordered), in: .init(identity: testIdentity("Root")))

    #expect(
      Set(originalResolved.children.map(\.identity))
        == Set(reorderedResolved.children.map(\.identity)))
    #expect(
      reorderedResolved.children.map(\.identity) == [
        testIdentity("Root", "VStack[0]", "ID[\"blue\"]"),
        testIdentity("Root", "VStack[0]", "ID[\"red\"]"),
        testIdentity("Root", "VStack[0]", "ID[\"green\"]"),
      ])

    let artifacts = DefaultRenderer().render(
      makeRoot(reordered),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.rasterSurface.lines == ["Blue", " Red", "Green"])
  }

  @Test("AnyLayout preserves child identity while switching layout policy")
  func anyLayoutPreservesIdentityAcrossSwitches() {
    let horizontal = AnyLayout(HStackLayout(spacing: 1))
    let vertical = AnyLayout(VStackLayout(spacing: 1))
    let makeRoot = { (layout: AnyLayout) in
      layout {
        Text("A")
        Text("B")
      }
    }

    let horizontalResolved = Resolver().resolve(
      makeRoot(horizontal), in: .init(identity: testIdentity("Root")))
    let verticalResolved = Resolver().resolve(
      makeRoot(vertical), in: .init(identity: testIdentity("Root")))
    let horizontalArtifacts = DefaultRenderer().render(
      makeRoot(horizontal),
      context: .init(identity: testIdentity("Horizontal"))
    )
    let verticalArtifacts = DefaultRenderer().render(
      makeRoot(vertical),
      context: .init(identity: testIdentity("Vertical"))
    )

    #expect(horizontalResolved.kind == .view("HStackLayout"))
    #expect(verticalResolved.kind == .view("VStackLayout"))
    #expect(
      horizontalResolved.children.map(\.identity) == [
        testIdentity("Root", "Layout[0]"),
        testIdentity("Root", "Layout[1]"),
      ])
    #expect(
      verticalResolved.children.map(\.identity) == [
        testIdentity("Root", "Layout[0]"),
        testIdentity("Root", "Layout[1]"),
      ])
    #expect(
      horizontalArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 2, y: 0),
      ])
    #expect(
      verticalArtifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 0, y: 2),
      ])
  }

  @Test("AnyLayout flattens direct ForEach output into sibling layout subviews")
  func anyLayoutFlattensForEachChildren() {
    let root = AnyLayout(HStackLayout(spacing: 1)) {
      Text("A")
      ForEach(["B", "C"], id: \.self) { value in
        Text(value)
      }
    }

    let resolved = Resolver().resolve(
      root,
      in: .init(identity: testIdentity("Root"))
    )
    let artifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(resolved.kind == .view("HStackLayout"))
    #expect(resolved.children.map(resolvedNodeLabelText(from:)) == ["A", "B", "C"])
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 2, y: 0),
        .init(x: 4, y: 0),
      ])
    #expect(artifacts.rasterSurface.lines == ["A B C"])
  }

  @Test("custom Layout reads layout values and places subviews explicitly")
  func customLayoutReadsLayoutValuesAndPlacesSubviews() {
    let artifacts = DefaultRenderer().render(
      GappedRowLayout {
        Text("A").layoutValue(key: GapAfterKey.self, value: 2)
        Text("B")
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.resolvedTree.kind == .view("GappedRowLayout"))
    #expect(
      artifacts.resolvedTree.children[0].layoutMetadata.layoutValues == [
        String(reflecting: GapAfterKey.self): "2"
      ])
    #expect(artifacts.measuredTree.measuredSize == .init(width: 4, height: 1))
    #expect(
      artifacts.placedTree.children.map(\.bounds.origin) == [
        .init(x: 0, y: 0),
        .init(x: 3, y: 0),
      ])
    #expect(artifacts.rasterSurface.lines == ["A  B"])
  }

  @Test("custom Layout reuses cache between measurement and placement")
  func customLayoutReusesCacheBetweenMeasurementAndPlacement() {
    let counter = LayoutCacheCounter()

    let artifacts = DefaultRenderer().render(
      CacheTrackingLayout(counter: counter) {
        Text("A")
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 1, height: 1))
    #expect(counter.makeCalls == 1)
    #expect(counter.lastMeasuredCache == 1)
    #expect(counter.lastPlacedCache == 1)
  }

  @Test("shared AnyLayout instances keep cache scoped to each container")
  func sharedAnyLayoutInstancesKeepCacheScopedPerContainer() {
    let recorder = SharedLayoutCacheRecorder()
    let sharedLayout = AnyLayout(WidthStampingLayout(recorder: recorder))

    _ = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        sharedLayout {
          Text("A")
        }
        sharedLayout {
          Text("BBBB")
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    #expect(recorder.placedValues == [1, 4])
  }
}

private func isAppear(_ operation: LifecycleCommitOperation) -> Bool {
  if case .appear = operation {
    return true
  }
  return false
}

private func isDisappear(_ operation: LifecycleCommitOperation) -> Bool {
  if case .disappear = operation {
    return true
  }
  return false
}

private func isTaskStart(_ operation: LifecycleCommitOperation) -> Bool {
  if case .taskStart = operation {
    return true
  }
  return false
}

private func isTaskCancel(_ operation: LifecycleCommitOperation) -> Bool {
  if case .taskCancel = operation {
    return true
  }
  return false
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}
