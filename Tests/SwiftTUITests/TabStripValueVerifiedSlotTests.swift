@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Focus-presentation value-verified slots: a focus move onto/off a `TabView`
/// makes the container a full suppression-scope member (it is a genuine
/// runtime-focus reader), and its body re-run recomputes every strip item —
/// although only the arriving/departing focused item's configuration changed.
///
/// The narrowing: the control declares its strip item routes as
/// *value-verified* slots. Descendants below one are exempt from the
/// focus-member dirty-queue walk and from the **memoized** (value-verified)
/// reuse denial — but never from value-blind Layer-A denial, so an item whose
/// configuration flipped fails the memo value compare and recomputes fresh.
/// Ancestor-of-member and exact-member scope matches are never exempted:
/// a wholesale focus reader (`isFocused` bake / `@Environment` wrapper)
/// inside an item is a scope member in its own right and keeps its cone.
@MainActor
@Suite(.serialized)
struct TabStripValueVerifiedSlotTests {
  @Test("a focus arrival onto the strip spares unchanged strip items")
  func focusArrivalOntoStripSparesUnchangedItems() throws {
    let harness = try ValueVerifiedSlotHarness(
      rootLabel: "ValueVerifiedSpareRoot"
    ) { counters in
      StripProbeRoot(counters: counters)
    }
    defer { harness.tearDown() }

    // Initial adoption focuses the outside text; the strip renders unfocused.
    let outsideIdentity = try #require(harness.focusedIdentity)
    let frameBefore = try #require(harness.lastFrame)
    #expect(!frameBefore.contains("[Zero]"))
    let countsBefore = harness.counters.counts

    // Focus arrives at the TabView container. Item 0 (the remembered strip
    // focus) flips its configuration and MUST recompute; items 1 and 2 are
    // value-identical and must be memo-reused, not recomputed.
    try harness.moveFocusNext()
    #expect(harness.focusedIdentity != outsideIdentity)
    let frameFocused = try #require(harness.lastFrame)
    #expect(frameFocused.contains("[Zero]"))
    #expect(
      harness.counters.count(for: 1) == (countsBefore[1] ?? 0),
      """
      strip item 1 re-evaluated \
      \(harness.counters.count(for: 1) - (countsBefore[1] ?? 0)) time(s) on \
      a focus arrival that did not change its configuration; the value-verified \
      slot should have memo-reused it
      """
    )
    #expect(harness.counters.count(for: 2) == (countsBefore[2] ?? 0))
    #expect(
      harness.counters.count(for: 0) > (countsBefore[0] ?? 0),
      "the arriving focused item must recompute to render its focus marker"
    )

    // Focus departs the strip: item 0 flips back (marker clears, recompute);
    // items 1 and 2 stay spared.
    let countsFocused = harness.counters.counts
    try harness.moveFocusPrevious()
    #expect(harness.focusedIdentity == outsideIdentity)
    let frameAfter = try #require(harness.lastFrame)
    #expect(!frameAfter.contains("[Zero]"))
    #expect(harness.counters.count(for: 0) > (countsFocused[0] ?? 0))
    #expect(harness.counters.count(for: 1) == (countsFocused[1] ?? 0))
    #expect(harness.counters.count(for: 2) == (countsFocused[2] ?? 0))
  }

  @Test("the tab content slot stays spared across strip focus arrivals")
  func contentSlotStaysSparedAcrossArrivals() throws {
    let harness = try ValueVerifiedSlotHarness(
      rootLabel: "ValueVerifiedContentRoot"
    ) { counters in
      StripProbeRoot(counters: counters)
    }
    defer { harness.tearDown() }

    // Regression pin for the existing focus-presentation-inert content slot:
    // the value-verified strip slots must not disturb it.
    let contentEvaluationsBefore = harness.counters.contentCount
    try harness.moveFocusNext()
    try harness.moveFocusPrevious()
    #expect(harness.counters.contentCount == contentEvaluationsBefore)
  }

  @Test("a wholesale focus reader inside a strip item keeps its cone")
  func bakeReaderInsideStripItemKeepsItsCone() throws {
    let harness = try ValueVerifiedSlotHarness(
      rootLabel: "ValueVerifiedBakeRoot"
    ) { counters in
      BakeReaderStripRoot(counters: counters)
    }
    defer { harness.tearDown() }

    // The item view hosts a descendant that reads `isFocused` (the containment
    // bake — a wholesale runtime-focus dependency). A focus arrival at the
    // container flips that descendant's baked value, so it MUST re-evaluate:
    // the reader is a full scope member and the item is its ancestor, which
    // the value-verified exemption never covers. This is the soundness
    // boundary pin — it must hold BEFORE and AFTER the narrowing.
    let bakeEvaluationsBefore = harness.counters.count(for: bakeProbeIndex)
    try harness.moveFocusNext()
    #expect(
      harness.counters.count(for: bakeProbeIndex) > bakeEvaluationsBefore,
      """
      the isFocused-reading probe inside a strip item did not re-evaluate on \
      a focus arrival at the container; a wholesale focus reader inside a \
      value-verified slot must keep its recompute cone
      """
    )
  }
}

// MARK: - Fixtures

/// Index used by the bake-reader fixture's probe counter (outside the real
/// item index range).
private let bakeProbeIndex = 99
/// Index used by the tab-content probe counter.
private let contentProbeIndex = 100

@MainActor
private final class StripEvaluationCounters {
  private(set) var counts: [Int: Int] = [:]

  func record(index: Int) {
    counts[index, default: 0] += 1
  }

  func count(for index: Int) -> Int {
    counts[index] ?? 0
  }

  var contentCount: Int {
    counts[contentProbeIndex] ?? 0
  }
}

private struct ContentProbeView: View {
  let counters: StripEvaluationCounters

  var body: some View {
    counters.record(index: contentProbeIndex)
    return Text("content probe")
  }
}

/// One outside focusable so initial adoption lands off the strip; a probe
/// style whose per-item views count their evaluations and render a
/// deterministic focused marker.
private struct StripProbeRoot: View {
  let counters: StripEvaluationCounters
  @State private var selection = 0

  var body: some View {
    VStack {
      Text("outside").focusable()
      TabView(selection: $selection) {
        Tab("Zero", value: 0) {
          ContentProbeView(counters: counters)
        }
        Tab("One", value: 1) {
          Text("second tab content")
        }
        Tab("Two", value: 2) {
          Text("third tab content")
        }
      }
      .tabViewStyle(ProbeTabViewStyle(counters: counters))
    }
  }
}

private struct BakeReaderStripRoot: View {
  let counters: StripEvaluationCounters
  @State private var selection = 0

  var body: some View {
    VStack {
      Text("outside").focusable()
      TabView(selection: $selection) {
        Tab("Zero", value: 0) {
          Text("first tab content")
        }
        Tab("One", value: 1) {
          Text("second tab content")
        }
      }
      .tabViewStyle(BakeReaderTabViewStyle(counters: counters))
    }
  }
}

private struct ProbeTabViewStyle: TabViewStyle, Equatable {
  let counters: StripEvaluationCounters

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.counters === rhs.counters
  }

  var snapshotLabel: String {
    "ProbeTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    ProbeTabStyleBody(configuration: configuration, counters: counters)
  }
}

private struct ProbeTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration
  let counters: StripEvaluationCounters

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            ProbeStripItemView(item: item, counters: counters)
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}

/// The memo boundary: `Equatable` over the item configuration; the counter is
/// compared by object identity (it is the same instance every frame).
private struct ProbeStripItemView: View, Equatable {
  let item: TabViewStyleItemConfiguration
  let counters: StripEvaluationCounters

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.item == rhs.item && lhs.counters === rhs.counters
  }

  var body: some View {
    counters.record(index: item.index)
    return Text(
      item.isFocused
        ? "[\(item.label.displayText)]"
        : " \(item.label.displayText) "
    )
  }
}

private struct BakeReaderTabViewStyle: TabViewStyle, Equatable {
  let counters: StripEvaluationCounters

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.counters === rhs.counters
  }

  var snapshotLabel: String {
    "BakeReaderTabViewStyle"
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    BakeReaderTabStyleBody(configuration: configuration, counters: counters)
  }
}

private struct BakeReaderTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration
  let counters: StripEvaluationCounters

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 1) {
        ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            BakeReaderStripItemView(item: item, counters: counters)
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}

/// Equatable-equal across the move (its stored values never change), but its
/// interior hosts a wholesale focus reader — memo must never fire over it.
private struct BakeReaderStripItemView: View, Equatable {
  let item: TabViewStyleItemConfiguration
  let counters: StripEvaluationCounters

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.item.index == rhs.item.index && lhs.counters === rhs.counters
  }

  var body: some View {
    HStack(spacing: 0) {
      Text(" \(item.label.displayText) ")
      BakeReadingProbe(counters: counters)
    }
  }
}

private struct BakeReadingProbe: View {
  @Environment(\.isFocused) private var isFocused
  let counters: StripEvaluationCounters

  var body: some View {
    counters.record(index: bakeProbeIndex)
    return Text(isFocused ? "*" : ".")
  }
}

// MARK: - Harness

@MainActor
private final class ValueVerifiedSlotHarness<Root: View> {
  let counters = StripEvaluationCounters()
  private let terminal: RecordingPresentationSurface
  private let runLoop: RunLoop<Int, Root>
  private var renderedFrames = 0

  init(
    rootLabel: String,
    viewBuilder: @escaping @MainActor (StripEvaluationCounters) -> Root
  ) throws {
    let terminalSize = CellSize(width: 72, height: 16)
    let terminal = RecordingPresentationSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity(rootLabel)
    var environmentValues = EnvironmentValues()
    environmentValues.terminalAppearance = terminal.appearance
    environmentValues.terminalSize = terminalSize
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let counters = counters
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ValueVerifiedSlotInputReader(),
      signalReader: ImmediateFinishSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      environmentValues: environmentValues,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder(counters) }
    )
    runLoop.installFocusTrackerInvalidator()
    runLoop.frameReadinessClock = { .now().advanced(by: .seconds(3600)) }
    self.terminal = terminal
    self.runLoop = runLoop

    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
    // Drain focus-adoption follow-ups, then render once more from the root
    // so the steady-state frame includes the adopted focus presentation.
    try settle()
    runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
    try settle()
  }

  func tearDown() {}

  var focusedIdentity: Identity? {
    runLoop.focusTracker.currentFocusIdentity
  }

  var lastFrame: String? {
    terminal.frames.last
  }

  func settle(maxDrains: Int = 5) throws {
    for _ in 0..<maxDrains {
      let before = renderedFrames
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      if renderedFrames == before {
        return
      }
    }
  }

  func moveFocusNext() throws {
    runLoop.focusTracker.focusNext()
    try settle()
  }

  func moveFocusPrevious() throws {
    runLoop.focusTracker.focusPrevious()
    try settle()
  }
}

private final class ValueVerifiedSlotInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
