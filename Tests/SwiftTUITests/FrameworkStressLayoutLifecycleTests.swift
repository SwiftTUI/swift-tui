import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI layout and lifecycle stress behavior", .serialized)
struct FrameworkStressLayoutLifecycleTests {}

@MainActor
private final class StressLayoutLifecycleProbe {
  var events: [String] = []
  var count = 0
  var secondaryCount = 0
}

// MARK: - Attempt 001: ViewThatFits selection churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 001 ViewThatFits selection tracks changing candidate fit")
  func stress001ViewThatFitsSelectionTracksChangingCandidateFit() throws {
    // Hypothesis: retained layout may keep the previously selected candidate
    // after the first candidate crosses the proposal boundary.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL001", "Root"),
      size: .init(width: 40, height: 8)
    ) {
      StressLL001Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      let frame = try harness.clickText("Toggle Fit")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("primary \(generation)"))
        #expect(!frame.contains("fallback \(generation)"))
      } else {
        #expect(frame.contains("fallback \(generation)"))
        #expect(!frame.contains("primary \(generation)"))
      }
      #expect(harness.lifecycleRegistrationCount <= 2)
    }
  }
}

@MainActor
private struct StressLL001Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Fit") { generation += 1 }
      ViewThatFits(in: .horizontal) {
        Text("primary \(generation)")
          .frame(width: generation.isMultiple(of: 2) ? 18 : 60)
        Text("fallback \(generation)")
          .frame(width: 18)
      }
      .frame(width: 24, height: 2, alignment: .topLeading)
    }
  }
}

// MARK: - Attempt 002: retained scrolling after content resize

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 002 retained scroll placement follows resized content")
  func stress002RetainedScrollPlacementFollowsResizedContent() throws {
    // Hypothesis: viewport-translation reuse may retain the target's old
    // placement when its height changes before a scroll-to command.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL002", "Root"),
      size: .init(width: 42, height: 10)
    ) {
      StressLL002Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Resize Target")
      let frame = try harness.clickText("Reveal Target")
      let height = generation.isMultiple(of: 2) ? 1 : 3
      #expect(frame.contains("target \(generation) height \(height)"))
      #expect(harness.scrollPositionRegistrationCount == 1)
    }
  }
}

@MainActor
private struct StressLL002Fixture: View {
  @State private var generation = 0

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Resize Target") { generation += 1 }
          Button("Reveal Target") { _ = proxy.scrollTo("target", anchor: .center) }
        }
        ScrollView(.vertical, showsIndicators: true) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<7, id: \.self) { row in
              Text("prefix \(row)")
            }
            Text(
              "target \(generation) height \(generation.isMultiple(of: 2) ? 1 : 3)"
            )
            .frame(height: generation.isMultiple(of: 2) ? 1 : 3, alignment: .topLeading)
            .id("target")
            ForEach(7..<12, id: \.self) { row in
              Text("suffix \(row)")
            }
          }
        }
        .frame(width: 40, height: 6, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 003: lazy rows inserted before the viewport

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 003 lazy viewport keeps stable row after prefix insertion")
  func stress003LazyViewportKeepsStableRowAfterPrefixInsertion() throws {
    // Hypothesis: indexed lazy placement may make a stable offscreen row
    // undiscoverable after new siblings are inserted ahead of the viewport.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL003", "Root"),
      size: .init(width: 38, height: 10)
    ) {
      StressLL003Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Prepend Row")
      let frame = try harness.clickText("Reveal Stable")
      withKnownIssue("ScrollViewReader cannot reveal an unplaced stable row in a LazyVStack") {
        #expect(frame.contains("stable row 10 first \(-generation)"))
      }
      #expect(harness.scrollPositionRegistrationCount == 1)
      #expect(harness.lifecycleRegistrationCount <= 2)
    }
  }
}

@MainActor
private struct StressLL003Fixture: View {
  @State private var firstRow = 0

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Prepend Row") { firstRow -= 1 }
          Button("Reveal Stable") { _ = proxy.scrollTo(10, anchor: .center) }
        }
        ScrollView(.vertical, showsIndicators: true) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(firstRow...24), id: \.self) { row in
              if row == 10 {
                Text("stable row 10 first \(firstRow)")
                  .id(row)
                  .onAppear {}
                  .onDisappear {}
              } else {
                Text("row \(row)")
                  .id(row)
              }
            }
          }
        }
        .frame(width: 36, height: 6, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 004: custom layout value churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 004 custom layout placement follows current layout value")
  func stress004CustomLayoutPlacementFollowsCurrentLayoutValue() throws {
    // Hypothesis: a retained custom-layout snapshot may keep the first
    // placement algorithm when only a layout value changes.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL004", "Root"),
      size: .init(width: 36, height: 7)
    ) {
      StressLL004Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Reverse Layout")
      let a = try #require(harness.point(forText: "Alpha"))
      let b = try #require(harness.point(forText: "Beta"))
      if generation.isMultiple(of: 2) {
        #expect(a.x < b.x)
      } else {
        #expect(b.x < a.x)
      }
    }
  }
}

@MainActor
private struct StressLL004Fixture: View {
  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse Layout") { reversed.toggle() }
      StressLL004Layout(reversed: reversed) {
        Text("Alpha")
        Text("Beta")
      }
      .frame(width: 30, height: 2, alignment: .topLeading)
    }
  }
}

private struct StressLL004Layout: Layout {
  var reversed: Bool

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return .init(
      width: sizes.reduce(0) { $0 + $1.width } + max(0, sizes.count - 1),
      height: sizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let order = reversed ? Array(subviews.indices.reversed()) : Array(subviews.indices)
    var x = bounds.origin.x
    for index in order {
      let size = subviews[index].sizeThatFits(.unspecified)
      subviews[index].place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      x += size.width + 1
    }
  }
}

// MARK: - Attempt 005: offset and position entity churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 005 stable entity uses current offset or position placement")
  func stress005StableEntityUsesCurrentOffsetOrPositionPlacement() throws {
    // Hypothesis: placement reuse may retain an entity's prior layout behavior
    // when offset and position reserve the same outer size.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL005", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressLL005Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Toggle Placement")
      let point = try #require(harness.point(forText: "Moving Target"))
      if generation.isMultiple(of: 2) {
        #expect(point.x < 20)
      } else {
        #expect(point.x > 20)
      }
      let frame = try harness.click(point)
      #expect(frame.contains("activations \(generation)"))
      #expect(harness.actionRegistrationCount <= 2)
    }
  }
}

@MainActor
private struct StressLL005Fixture: View {
  @State private var usesPosition = false
  @State private var activations = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Placement") { usesPosition.toggle() }
      Text("activations \(activations)")
      ZStack(alignment: .topLeading) {
        if usesPosition {
          Button("Moving Target") { activations += 1 }
            .id("moving-target")
            .position(x: 30, y: 1)
        } else {
          Button("Moving Target") { activations += 1 }
            .id("moving-target")
            .offset(x: 2, y: 0)
        }
      }
      .frame(width: 42, height: 5, alignment: .topLeading)
    }
  }
}

// MARK: - Attempt 006: noncommutative preference reordering

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 006 preference reduction follows current sibling order")
  func stress006PreferenceReductionFollowsCurrentSiblingOrder() throws {
    // Hypothesis: retained sibling snapshots may replay preferences in their
    // original order after stable-ID children move.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL006", "Root"),
      size: .init(width: 38, height: 8)
    ) {
      StressLL006Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Reverse Writers")
      let expected = generation.isMultiple(of: 2) ? "AB" : "BA"
      #expect(frame.contains("reduced \(expected) generation \(generation)"))
    }
  }
}

private enum StressLL006PreferenceKey: PreferenceKey {
  static let defaultValue = ""

  static func reduce(value: inout String, nextValue: () -> String) {
    value += nextValue()
  }
}

@MainActor
private struct StressLL006Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse Writers") { generation += 1 }
      VStack(alignment: .leading, spacing: 0) {
        if generation.isMultiple(of: 2) {
          writer("A")
          writer("B")
        } else {
          writer("B")
          writer("A")
        }
      }
      .frame(width: 36, height: 4, alignment: .topLeading)
      .overlayPreferenceValue(StressLL006PreferenceKey.self, alignment: .bottomLeading) { value in
        Text("reduced \(value) generation \(generation)")
      }
    }
  }

  private func writer(_ value: String) -> some View {
    Text("writer \(value)")
      .id(value)
      .preference(key: StressLL006PreferenceKey.self, value: value)
  }
}

// MARK: - Attempt 007: preference observer ordinal contraction

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 007 surviving preference observer keeps its own baseline")
  func stress007SurvivingPreferenceObserverKeepsItsOwnBaseline() throws {
    // Hypothesis: when observer A disappears, observer B may inherit A's
    // ordinal and previous-value snapshot instead of its own registration.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL007", "Root"),
      size: .init(width: 42, height: 8)
    ) {
      StressLL007Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      _ = try harness.clickText("Churn Observers")
      #expect(probe.events.filter { $0.hasPrefix("B:") }.count == generation)
      #expect(probe.events.contains("B:\(generation)"))
      #expect(
        probe.events.contains("A:\(generation)") == generation.isMultiple(of: 2)
      )
      #expect(harness.preferenceObservationRegistrationCount <= 2)
    }
  }
}

private enum StressLL007PreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

@MainActor
private struct StressLL007Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Churn Observers") { generation += 1 }
      observedSource
    }
  }

  @ViewBuilder private var observedSource: some View {
    if generation.isMultiple(of: 2) {
      source
        .onPreferenceChange(StressLL007PreferenceKey.self) { value in
          probe.events.append("A:\(value)")
        }
        .onPreferenceChange(StressLL007PreferenceKey.self) { value in
          probe.events.append("B:\(value)")
        }
    } else {
      source
        .onPreferenceChange(StressLL007PreferenceKey.self) { value in
          probe.events.append("B:\(value)")
        }
    }
  }

  private var source: some View {
    Text("observer generation \(generation)")
      .preference(key: StressLL007PreferenceKey.self, value: generation)
  }
}

// MARK: - Attempt 008: anchor payload after owner remint

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 008 anchor resolves the current reminted source node")
  func stress008AnchorResolvesTheCurrentRemintedSourceNode() throws {
    // Hypothesis: an anchor preference may retain the departed source's
    // viewNodeID and resolve its previous frame after owner identity churn.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL008", "Root"),
      size: .init(width: 40, height: 8)
    ) {
      StressLL008Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Remint Anchor")
      let expectedX = generation.isMultiple(of: 2) ? 2 : 14
      #expect(frame.contains("anchor x \(expectedX) generation \(generation)"))
    }
  }
}

private enum StressLL008AnchorKey: PreferenceKey {
  static let defaultValue: Anchor<Rect>? = nil

  static func reduce(
    value: inout Anchor<Rect>?,
    nextValue: () -> Anchor<Rect>?
  ) {
    value = nextValue() ?? value
  }
}

@MainActor
private struct StressLL008Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Remint Anchor") { generation += 1 }
      Group {
        Text("anchor source")
          .frame(width: 8, height: 1, alignment: .topLeading)
          .id("anchor-source")
          .anchorPreference(key: StressLL008AnchorKey.self, value: .bounds) { $0 }
          .offset(x: generation.isMultiple(of: 2) ? 2 : 14)
      }
      .id("anchor-owner-\(generation)")
      .frame(width: 38, height: 4, alignment: .topLeading)
      .overlayPreferenceValue(StressLL008AnchorKey.self, alignment: .bottomLeading) { anchor in
        GeometryReader { proxy in
          let rect = anchor.map { proxy[$0] } ?? .zero
          Text("anchor x \(Int(rect.origin.x)) generation \(generation)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
      }
    }
  }
}

// MARK: - Attempt 009: toolbar item migration across late hosts

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 009 late toolbar item migrates between nested hosts")
  func stress009LateToolbarItemMigratesBetweenNestedHosts() throws {
    // Hypothesis: recursive late-preference reconciliation may leave an item
    // absorbed by its former host after the inner toolbar disappears.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL009", "Root"),
      size: .init(width: 56, height: 12)
    ) {
      StressLL009Fixture()
    }
    defer { harness.shutdown() }

    var expectedTotal = 0
    for generation in 1...8 {
      var frame = try harness.clickText("Move Toolbar Item")
      #expect(frame.components(separatedBy: "Run \(generation)").count - 1 == 1)
      frame = try harness.clickText("Run \(generation)", chooseLast: true)
      expectedTotal += generation + 1
      #expect(frame.contains("toolbar total \(expectedTotal)"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressLL009Fixture: View {
  @State private var generation = 0
  @State private var total = 0

  var body: some View {
    Panel(id: "outer-toolbar") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Move Toolbar Item") { generation += 1 }
        Text("toolbar total \(total)")
        if generation.isMultiple(of: 2) {
          Panel(id: "inner-toolbar") {
            lateItemSource
          }
          .toolbar(style: DefaultBottomToolbarStyle())
        } else {
          lateItemSource
        }
      }
    }
    .toolbar(style: DefaultTopToolbarStyle())
    .frame(width: 54, height: 10, alignment: .topLeading)
  }

  private var lateItemSource: some View {
    GeometryReader { proxy in
      Text("late body \(generation) \(proxy.size.width)x\(proxy.size.height)")
        .toolbarItem(
          .init(
            title: "Run \(generation)",
            icon: nil,
            position: .top,
            isEnabled: true,
            action: { total += generation + 1 }
          )
        )
    }
  }
}

// MARK: - Attempt 010: same-ID navigation payload refresh

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 010 active navigation item refreshes same ID payload")
  func stress010ActiveNavigationItemRefreshesSameIDPayload() throws {
    // Hypothesis: a stable activation identity may retain the first item
    // payload and action closure when only the item's non-ID fields change.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL010", "Root"),
      size: .init(width: 46, height: 10)
    ) {
      StressLL010Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Item Destination")
    for version in 1...8 {
      _ = try harness.clickText("Increment Destination Local")
      let frame = try harness.clickText("Refresh Item Payload")
      #expect(frame.contains("item version \(version) local \(version)"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

private struct StressLL010Item: Identifiable, Sendable {
  let id = 1
  var version: Int
}

@MainActor
private struct StressLL010Fixture: View {
  @State private var item: StressLL010Item?

  var body: some View {
    NavigationStack(id: "stress-010-navigation") {
      Button("Open Item Destination") {
        item = StressLL010Item(version: 0)
      }
      .navigationDestination(item: $item) { item in
        StressLL010Destination(item: item, activeItem: $item)
      }
    }
  }
}

@MainActor
private struct StressLL010Destination: View {
  let item: StressLL010Item
  @Binding var activeItem: StressLL010Item?
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("item version \(item.version) local \(local)")
      Button("Increment Destination Local") { local += 1 }
      Button("Refresh Item Payload") {
        activeItem = StressLL010Item(version: item.version + 1)
      }
    }
  }
}

// MARK: - Attempt 011: navigation reactivation identity

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 011 navigation reactivation starts fresh destination state")
  func stress011NavigationReactivationStartsFreshDestinationState() throws {
    // Hypothesis: repeated Boolean destination activation may reuse a prior
    // activation's state slots after its route was popped.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL011", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressLL011Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...8 {
      var frame = try harness.clickText("Open Fresh Destination")
      #expect(frame.contains("fresh local 0"))
      frame = try harness.clickText("Increment Fresh Local")
      #expect(frame.contains("fresh local 1"))
      frame = try harness.clickText("Close Fresh Destination")
      #expect(!frame.contains("fresh local"))
      #expect(harness.actionRegistrationCount <= 1)
    }
  }
}

@MainActor
private struct StressLL011Fixture: View {
  @State private var isPresented = false

  var body: some View {
    NavigationStack(id: "stress-011-navigation") {
      Button("Open Fresh Destination") { isPresented = true }
        .navigationDestination(isPresented: $isPresented) {
          StressLL011Destination(isPresented: $isPresented)
        }
    }
  }
}

@MainActor
private struct StressLL011Destination: View {
  @Binding var isPresented: Bool
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("fresh local \(local)")
      Button("Increment Fresh Local") { local += 1 }
      Button("Close Fresh Destination") { isPresented = false }
    }
  }
}

// MARK: - Attempt 012: navigation declaration order churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 012 reordered active destinations keep last-wins pop routing")
  func stress012ReorderedActiveDestinationsKeepLastWinsPopRouting() throws {
    // Hypothesis: retained destination preferences may preserve the old
    // declaration order or pop closure after stable sources reorder.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL012", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      StressLL012Fixture()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("visible destination B"))
    for generation in 1...6 {
      let frame = try harness.clickText("Reverse Destination Order")
      let expected = generation.isMultiple(of: 2) ? "B" : "A"
      #expect(frame.contains("visible destination \(expected)"))
    }

    let popped = try harness.clickText("Close B")
    #expect(popped.contains("visible destination A"))
    #expect(!popped.contains("visible destination B"))
  }
}

@MainActor
private struct StressLL012Fixture: View {
  @State private var firstActive = true
  @State private var secondActive = true
  @State private var reversed = false

  var body: some View {
    NavigationStack(id: "stress-012-navigation") {
      VStack(alignment: .leading, spacing: 0) {
        if reversed {
          secondSource
          firstSource
        } else {
          firstSource
          secondSource
        }
      }
    }
  }

  private var firstSource: some View {
    Text("source A")
      .id("source-a")
      .navigationDestination(isPresented: $firstActive) {
        StressLL012Destination(
          label: "A",
          reversed: $reversed,
          isPresented: $firstActive
        )
      }
  }

  private var secondSource: some View {
    Text("source B")
      .id("source-b")
      .navigationDestination(isPresented: $secondActive) {
        StressLL012Destination(
          label: "B",
          reversed: $reversed,
          isPresented: $secondActive
        )
      }
  }
}

@MainActor
private struct StressLL012Destination: View {
  let label: String
  @Binding var reversed: Bool
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("visible destination \(label)")
      Button("Reverse Destination Order") { reversed.toggle() }
      Button("Close \(label)") { isPresented = false }
    }
  }
}

// MARK: - Attempt 013: hidden navigation root freshness

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 013 hidden navigation root returns with current state")
  func stress013HiddenNavigationRootReturnsWithCurrentState() throws {
    // Hypothesis: the detached hosted root may return with a stale snapshot or
    // a duplicate task after it is mutated while a destination is visible.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL013", "Root"),
      size: .init(width: 44, height: 9)
    ) {
      StressLL013Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Push Hidden Root")
      _ = try harness.clickText("Mutate Hidden Root")
      let frame = try harness.clickText("Pop Hidden Root")
      #expect(frame.contains("root model \(generation)"))
      #expect(harness.activeTaskCount == 1)
      #expect(harness.activeTaskDescriptorCount == 1)
    }
  }
}

@MainActor
private struct StressLL013Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var isPresented = false

  var body: some View {
    NavigationStack(id: "stress-013-navigation") {
      VStack(alignment: .leading, spacing: 0) {
        Text("root model \(probe.count)")
          .task(id: "hidden-root-task") {
            while !Task.isCancelled {
              await Task.yield()
            }
          }
        Button("Push Hidden Root") { isPresented = true }
      }
      .navigationDestination(isPresented: $isPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Button("Mutate Hidden Root") { probe.count += 1 }
          Button("Pop Hidden Root") { isPresented = false }
        }
      }
    }
  }
}

// MARK: - Attempt 014: stacked same-family sheets

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 014 dismissing newest sheet reveals older sheet")
  func stress014DismissingNewestSheetRevealsOlderSheet() throws {
    // Hypothesis: replacing a sheet-family overlay entry may discard or strand
    // the older active declaration instead of revealing it after dismissal.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL014", "Root"),
      size: .init(width: 52, height: 12)
    ) {
      StressLL014Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...6 {
      var frame = try harness.clickText("Open Sheet A")
      #expect(frame.contains("sheet A body"))
      frame = try harness.clickText("Open Sheet B", chooseLast: true)
      #expect(frame.contains("sheet B body"))
      #expect(!frame.contains("sheet A body"))
      frame = try harness.clickText("Close Sheet B", chooseLast: true)
      #expect(frame.contains("sheet A body"))
      #expect(!frame.contains("sheet B body"))
      frame = try harness.clickText("Close Sheet A", chooseLast: true)
      #expect(!frame.contains("sheet A body"))
      #expect(harness.lifecycleRegistrationCount <= 4)
    }
  }
}

@MainActor
private struct StressLL014Fixture: View {
  @State private var sheetA = false
  @State private var sheetB = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Open Sheet A") { sheetA = true }
      Text("base surface")
    }
    .sheet("Sheet A", isPresented: $sheetA) {
      VStack(alignment: .leading, spacing: 0) {
        Text("sheet A body")
        Button("Open Sheet B") { sheetB = true }
        Button("Close Sheet A") { sheetA = false }
      }
    }
    .sheet("Sheet B", isPresented: $sheetB) {
      VStack(alignment: .leading, spacing: 0) {
        Text("sheet B body")
        Button("Close Sheet B") { sheetB = false }
      }
    }
  }
}

// MARK: - Attempt 015: active sheet payload refresh

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 015 active sheet refreshes payload without losing local state")
  func stress015ActiveSheetRefreshesPayloadWithoutLosingLocalState() throws {
    // Hypothesis: a stable portal entry may reuse its first payload when the
    // source state changes, or remint the hosted state owner unnecessarily.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL015", "Root"),
      size: .init(width: 52, height: 11)
    ) {
      StressLL015Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Refreshing Sheet")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Sheet Local", chooseLast: true)
      let frame = try harness.clickText("Refresh Sheet Payload", chooseLast: true)
      #expect(frame.contains("sheet version \(generation) local \(generation)"))
      #expect(harness.actionRegistrationCount <= 4)
    }
  }
}

@MainActor
private struct StressLL015Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    Button("Open Refreshing Sheet") { isPresented = true }
      .sheet("Refreshing", isPresented: $isPresented) {
        StressLL015Sheet(
          generation: generation,
          generationBinding: $generation
        )
      }
  }
}

@MainActor
private struct StressLL015Sheet: View {
  let generation: Int
  @Binding var generationBinding: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sheet version \(generation) local \(local)")
      Button("Increment Sheet Local") { local += 1 }
      Button("Refresh Sheet Payload") { generationBinding += 1 }
    }
  }
}

// MARK: - Attempt 016: presented source identity remint

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 016 active sheet replaces reminted declaration source")
  func stress016ActiveSheetReplacesRemintedDeclarationSource() throws {
    // Hypothesis: old and new declarative source entries may coexist when the
    // presenting identity changes while its binding remains true.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL016", "Root"),
      size: .init(width: 54, height: 11)
    ) {
      StressLL016Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Reminted Sheet")
    for generation in 1...8 {
      let frame = try harness.clickText("Remint Sheet Source", chooseLast: true)
      #expect(frame.contains("reminted sheet generation \(generation)"))
      #expect(
        frame.components(separatedBy: "reminted sheet generation").count - 1 == 1
      )
      #expect(harness.lifecycleRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressLL016Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    Group {
      VStack(alignment: .leading, spacing: 0) {
        Text("source generation \(generation)")
        Button("Open Reminted Sheet") { isPresented = true }
      }
    }
    .id("sheet-source-\(generation)")
    .sheet("Reminted", isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("reminted sheet generation \(generation)")
        Button("Remint Sheet Source") { generation += 1 }
      }
    }
  }
}

// MARK: - Attempt 017: popover tracks moving source

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 017 open popover follows current source frame")
  func stress017OpenPopoverFollowsCurrentSourceFrame() throws {
    // Hypothesis: the portal GeometryReader may resolve a retained placed-frame
    // table and leave an open popover attached to the source's old position.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL017", "Root"),
      size: .init(width: 76, height: 12)
    ) {
      StressLL017Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Moving Popover")
    var previousX = try #require(harness.point(forText: "Move Popover Source")).x
    for offset in stride(from: 2, through: 12, by: 2) {
      let frame = try harness.clickText("Move Popover Source", chooseLast: true)
      let currentX = try #require(harness.point(forText: "Move Popover Source")).x
      withKnownIssue("An open popover retains its opening geometry and content closure") {
        #expect(currentX > previousX)
        #expect(frame.contains("popover source offset \(offset)"))
      }
      previousX = currentX
    }
  }
}

@MainActor
private struct StressLL017Fixture: View {
  @State private var isPresented = false
  @State private var sourceOffset = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("moving popover base")
      Button("Open Moving Popover") { isPresented = true }
        .offset(x: sourceOffset)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
          VStack(alignment: .leading, spacing: 0) {
            Text("popover source offset \(sourceOffset)")
            Button("Move Popover Source") { sourceOffset += 2 }
            Button("Close Moving Popover") { isPresented = false }
          }
        }
    }
  }
}

// MARK: - Attempt 018: logical tab focus across reorder

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 018 reordered tabs preserve logical focused tag")
  func stress018ReorderedTabsPreserveLogicalFocusedTag() throws {
    // Hypothesis: TabView stores strip focus as a raw index, so reordering
    // stable tags can silently retarget activation to another tab.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL018", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      StressLL018Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressLL018Fixture.tabIdentity)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.arrowRight))

    for _ in 1...6 {
      _ = try harness.clickText("Reverse Tabs")
      _ = try harness.focus(StressLL018Fixture.tabIdentity)
      let frame = try harness.pressKey(KeyPress(.return))
      #expect(frame.contains("selected tag C"))
      #expect(frame.contains("content C"))
    }
  }
}

@MainActor
private struct StressLL018Fixture: View {
  static let tabIdentity = testIdentity("StressLL018", "Tabs")

  @State private var selection = "A"
  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse Tabs") { reversed.toggle() }
      Text("selected tag \(selection)")
      TabView(selection: $selection) {
        if reversed {
          tab("C")
          tab("B")
          tab("A")
        } else {
          tab("A")
          tab("B")
          tab("C")
        }
      }
      .tabViewStyle(.literalTabs)
      .id(Self.tabIdentity)
      .frame(width: 48, height: 6, alignment: .topLeading)
    }
  }

  private func tab(_ value: String) -> some View {
    Tab("Tab \(value)", value: value) {
      Text("content \(value)")
    }
    .id(value)
  }
}

// MARK: - Attempt 019: removing a focused overflow tab

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 019 overflow routes drop a removed focused tab")
  func stress019OverflowRoutesDropARemovedFocusedTab() throws {
    // Hypothesis: an expanded overflow surface may retain the removed option's
    // item route and stored focus index after the options array contracts.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL019", "Root"),
      size: .init(width: 52, height: 11)
    ) {
      StressLL019Fixture()
    }
    defer { harness.shutdown() }

    var frame = harness.frame
    if !frame.contains("Fifth Extremely Long") {
      let initialTrigger = frame.contains("▼") ? "▼" : "▾"
      frame = try harness.clickText(initialTrigger)
    }
    #expect(frame.contains("Fifth Extremely Long"))

    for _ in 1...8 {
      let handlersWithFifth = harness.pointerHandlerCount
      frame = try harness.clickText("Toggle Fifth Tab")
      #expect(!frame.contains("Fifth Extremely Long"))
      #expect(harness.pointerHandlerCount < handlersWithFifth)

      frame = try harness.clickText("Toggle Fifth Tab")
      if !frame.contains("Fifth Extremely Long") {
        let restoredTrigger = frame.contains("▼") ? "▼" : "▾"
        frame = try harness.clickText(restoredTrigger)
      }
      #expect(frame.contains("Fifth Extremely Long"))
      frame = try harness.clickText("Fifth Extremely Long", chooseLast: true)
      #expect(frame.contains("selected overflow fifth"))
      #expect(harness.pointerHandlerCount <= 14)
    }
  }
}

@MainActor
private struct StressLL019Fixture: View {
  @State private var selection = "fifth"
  @State private var includesFifth = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Fifth Tab") { includesFifth.toggle() }
      Text("selected overflow \(selection)")
      TabView(selection: $selection) {
        overflowTab("First Extremely Long", value: "first")
        overflowTab("Second Extremely Long", value: "second")
        overflowTab("Third Extremely Long", value: "third")
        overflowTab("Fourth Extremely Long", value: "fourth")
        if includesFifth {
          overflowTab("Fifth Extremely Long", value: "fifth")
        }
      }
      .tabViewStyle(.literalTabs)
      .frame(width: 30, height: 7, alignment: .topLeading)
    }
  }

  private func overflowTab(_ label: String, value: String) -> some View {
    Tab(label, value: value) {
      Text("overflow content \(value)")
    }
    .id(value)
  }
}

// MARK: - Attempt 020: overflow disappearance across width churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 020 overflow menu collapses after overflow options disappear")
  func stress020OverflowMenuCollapsesAfterOptionsDisappear() throws {
    // Hypothesis: the expanded state slot is never cleared while the trailing
    // options disappear, so restoring them resurrects an open stale menu.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL020", "Root"),
      size: .init(width: 24, height: 11)
    ) {
      StressLL020Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...6 {
      var frame = try harness.clickText("▾")
      #expect(frame.contains("Four"))
      frame = try harness.clickText("Toggle Overflow Tabs")
      #expect(!frame.contains("Four"))
      frame = try harness.clickText("Toggle Overflow Tabs")
      #expect(frame.contains("▾"))
      #expect(!frame.contains("Four"))
      #expect(harness.pointerHandlerCount <= 9)
      if frame.contains("▴") {
        frame = try harness.clickText("▴")
        #expect(!frame.contains("Four"))
      }
    }
  }
}

@MainActor
private struct StressLL020Fixture: View {
  @State private var selection = "first"
  @State private var showsOverflowTabs = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Overflow Tabs") { showsOverflowTabs.toggle() }
      TabView(selection: $selection) {
        Tab("One", value: "first") { Text("first width content") }
        Tab("Two", value: "second") { Text("second width content") }
        if showsOverflowTabs {
          Tab("Three", value: "third") { Text("third width content") }
          Tab("Four", value: "fourth") { Text("fourth width content") }
        }
      }
      .tabViewStyle(.literalTabs)
      .frame(width: 24, height: 7, alignment: .topLeading)
    }
  }
}

// MARK: - Attempt 021: navigation teardown inside a sheet

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 021 dismissing sheet tears down nested navigation destination")
  func stress021DismissingSheetTearsDownNestedNavigationDestination() throws {
    // Hypothesis: a destination root detached by NavigationStack can outlive
    // the portal entry that hosts its navigation stack.
    let baseline = SoundnessProbeConfiguration.teardownCoherenceViolationCount
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL021", "Root"),
      size: .init(width: 54, height: 12)
    ) {
      StressLL021Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...6 {
      _ = try harness.clickText("Open Navigation Sheet")
      var frame = try harness.clickText("Push Sheet Detail", chooseLast: true)
      #expect(frame.contains("nested sheet detail"))
      #expect(harness.activeTaskCount == 1)
      frame = try harness.clickText("Dismiss Sheet From Detail", chooseLast: true)
      #expect(!frame.contains("nested sheet detail"))
      #expect(harness.activeTaskCount == 0)
      #expect(harness.actionRegistrationCount <= 1)
    }

    #expect(SoundnessProbeConfiguration.teardownCoherenceViolationCount == baseline)
  }
}

@MainActor
private struct StressLL021Fixture: View {
  @State private var isPresented = false

  var body: some View {
    Button("Open Navigation Sheet") { isPresented = true }
      .sheet("Navigation", isPresented: $isPresented) {
        StressLL021Sheet(isPresented: $isPresented)
      }
  }
}

@MainActor
private struct StressLL021Sheet: View {
  @Binding var isPresented: Bool
  @State private var showsDetail = false

  var body: some View {
    NavigationStack(id: "stress-021-navigation") {
      Button("Push Sheet Detail") { showsDetail = true }
        .navigationDestination(isPresented: $showsDetail) {
          VStack(alignment: .leading, spacing: 0) {
            Text("nested sheet detail")
              .task(id: "nested-sheet-detail-task") {
                while !Task.isCancelled {
                  await Task.yield()
                }
              }
            Button("Dismiss Sheet From Detail") { isPresented = false }
          }
        }
    }
  }
}

// MARK: - Attempt 022: onChange modifier reorder

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 022 reordered onChange modifiers keep semantic baselines")
  func stress022ReorderedOnChangeModifiersKeepSemanticBaselines() throws {
    // Hypothesis: identity-plus-ordinal storage may cross-wire the previous
    // values when two onChange modifiers exchange order.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL022", "Root"),
      size: .init(width: 48, height: 8)
    ) {
      StressLL022Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      _ = try harness.clickText("Mutate Reordered Changes")
      withKnownIssue("Reordered onChange modifiers exchange their ordinal baselines") {
        #expect(probe.events.contains("first:\(generation - 1)->\(generation)"))
        #expect(
          probe.events.contains("second:\((generation - 1) * 10)->\(generation * 10)")
        )
        #expect(probe.events.count == generation * 2)
      }
      #expect(harness.lifecycleRegistrationCount <= 2)
    }
  }
}

@MainActor
private struct StressLL022Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var first = 0
  @State private var second = 0
  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Mutate Reordered Changes") {
        first += 1
        second += 10
        reversed.toggle()
      }
      observedValue
        .id("reordered-change-source")
    }
  }

  @ViewBuilder private var observedValue: some View {
    if reversed {
      source
        .onChange(of: second) { old, new in
          probe.events.append("second:\(old)->\(new)")
        }
        .onChange(of: first) { old, new in
          probe.events.append("first:\(old)->\(new)")
        }
    } else {
      source
        .onChange(of: first) { old, new in
          probe.events.append("first:\(old)->\(new)")
        }
        .onChange(of: second) { old, new in
          probe.events.append("second:\(old)->\(new)")
        }
    }
  }

  private var source: some View {
    Text("change values \(first) \(second)")
  }
}

// MARK: - Attempt 023: cascading onChange writes

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 023 cascading onChange dispatches each transition once")
  func stress023CascadingOnChangeDispatchesEachTransitionOnce() throws {
    // Hypothesis: a change handler that schedules the next value can be
    // replayed from a stale registry snapshot or lose the second transition.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL023", "Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressLL023Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for cycle in 1...8 {
      let frame = try harness.clickText("Start Change Cascade")
      #expect(frame.contains("cascade value \(cycle * 2)"))
      #expect(probe.events.count == cycle * 2)
      #expect(probe.events[cycle * 2 - 2] == "\(cycle * 2 - 2)->\(cycle * 2 - 1)")
      #expect(probe.events[cycle * 2 - 1] == "\(cycle * 2 - 1)->\(cycle * 2)")
      #expect(harness.lifecycleRegistrationCount <= 1)
    }
  }
}

@MainActor
private struct StressLL023Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var value = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Start Change Cascade") { value += 1 }
      Text("cascade value \(value)")
        .onChange(of: value) { old, new in
          probe.events.append("\(old)->\(new)")
          if !new.isMultiple(of: 2) {
            value = new + 1
          }
        }
    }
  }
}

// MARK: - Attempt 024: onAppear removes its owner

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 024 onAppear self removal pairs disappear and task cancel")
  func stress024OnAppearSelfRemovalPairsDisappearAndTaskCancel() throws {
    // Hypothesis: post-commit invalidation from onAppear can skip the matching
    // disappearance or leave the just-started task alive.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL024", "Root"),
      size: .init(width: 42, height: 8)
    ) {
      StressLL024Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for cycle in 1...8 {
      let frame = try harness.clickText("Show Self Removing Branch")
      #expect(!frame.contains("self removing branch"))
      #expect(probe.events.count == cycle * 2)
      #expect(probe.events[cycle * 2 - 2] == "appear")
      #expect(probe.events[cycle * 2 - 1] == "disappear")
      #expect(harness.activeTaskCount == 0)
      #expect(harness.lifecycleRegistrationCount == 0)
    }
  }
}

@MainActor
private struct StressLL024Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var isVisible = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Show Self Removing Branch") { isVisible = true }
      if isVisible {
        Text("self removing branch")
          .task(id: "self-removing-task") {
            while !Task.isCancelled {
              await Task.yield()
            }
          }
          .onAppear {
            probe.events.append("appear")
            isVisible = false
          }
          .onDisappear {
            probe.events.append("disappear")
          }
      }
    }
  }
}

// MARK: - Attempt 025: lazy viewport lifecycle churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 025 lazy rows pair lifecycle while crossing viewport")
  func stress025LazyRowsPairLifecycleWhileCrossingViewport() throws {
    // Hypothesis: viewport lifecycle keys may accumulate or skip events when
    // the same indexed rows repeatedly leave and re-enter placement.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL025", "Root"),
      size: .init(width: 42, height: 10)
    ) {
      StressLL025Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for _ in 1...8 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Scroll Lazy Bottom")
      #expect(probe.events.filter { $0 == "row0 disappear" }.count == 1)
      _ = try harness.clickText("Scroll Lazy Top")
      #expect(probe.events.filter { $0 == "row0 appear" }.count == 1)
      #expect(harness.activeTaskCount <= 8)
      #expect(harness.scrollPositionRegistrationCount == 1)
    }
  }
}

@MainActor
private struct StressLL025Fixture: View {
  let probe: StressLayoutLifecycleProbe

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Scroll Lazy Bottom") { _ = proxy.scrollTo(edge: .bottom) }
          Button("Scroll Lazy Top") { _ = proxy.scrollTo(edge: .top) }
        }
        ScrollView(.vertical, showsIndicators: true) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { row in
              Text("lazy lifecycle row \(row)")
                .id(row)
                .onAppear {
                  if row == 0 { probe.events.append("row0 appear") }
                }
                .onDisappear {
                  if row == 0 { probe.events.append("row0 disappear") }
                }
                .task(id: row) {
                  while !Task.isCancelled {
                    await Task.yield()
                  }
                }
            }
          }
        }
        .frame(width: 40, height: 6, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 026: task descriptor and identity churn

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 026 task registry targets newest closure across identity churn")
  func stress026TaskRegistryTargetsNewestClosureAcrossIdentityChurn() async throws {
    // Hypothesis: identityChanged task diff suppression may leave the prior
    // descriptor's registration or closure live when both identity and ID move.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL026", "Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressLL026Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Churn Task Identity")
      let registrations = harness.runLoop.localTaskRegistry.snapshot().values.flatMap { $0 }
      let registration = try #require(registrations.first)
      #expect(registrations.count == 1)
      await registration.run()
      #expect(probe.events.last == "run:\(generation)")
    }
  }
}

private struct StressLL026TaskID: Equatable, Sendable {
  var generation: Int
}

@MainActor
private struct StressLL026Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Churn Task Identity") { generation += 1 }
      Text("task owner generation \(generation)")
        .id("task-owner-\(generation % 2)")
        .task(id: StressLL026TaskID(generation: generation)) {
          probe.events.append("run:\(generation)")
        }
    }
  }
}

// MARK: - Attempt 027: reordered multiple task modifiers

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 027 reordered task modifiers publish current closures")
  func stress027ReorderedTaskModifiersPublishCurrentClosures() async throws {
    // Hypothesis: ordinal-keyed task registrations may keep a prior semantic
    // task's closure after two modifiers exchange order.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL027", "Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressLL027Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Reorder Task Modifiers")
      let registrations = harness.runLoop.localTaskRegistry.snapshot().values.flatMap { $0 }
      #expect(registrations.count == 2)
      probe.events.removeAll(keepingCapacity: true)
      for registration in registrations {
        await registration.run()
      }
      #expect(probe.events.contains("A:\(generation)"))
      #expect(probe.events.contains("B:\(generation)"))
    }
  }
}

private struct StressLL027TaskID: Equatable, Sendable {
  var slot: String
  var generation: Int
}

@MainActor
private struct StressLL027Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Task Modifiers") { generation += 1 }
      taskOwner
    }
  }

  @ViewBuilder private var taskOwner: some View {
    if generation.isMultiple(of: 2) {
      source
        .task(id: StressLL027TaskID(slot: "A", generation: generation)) {
          probe.events.append("A:\(generation)")
        }
        .task(id: StressLL027TaskID(slot: "B", generation: generation)) {
          probe.events.append("B:\(generation)")
        }
    } else {
      source
        .task(id: StressLL027TaskID(slot: "B", generation: generation)) {
          probe.events.append("B:\(generation)")
        }
        .task(id: StressLL027TaskID(slot: "A", generation: generation)) {
          probe.events.append("A:\(generation)")
        }
    }
  }

  private var source: some View {
    Text("task modifier generation \(generation)")
      .id("reordered-task-owner")
  }
}

// MARK: - Attempt 028: nested disappearance ordering

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 028 nested removal dispatches child disappear before parent")
  func stress028NestedRemovalDispatchesChildDisappearBeforeParent() throws {
    // Hypothesis: structural teardown event partitioning may reorder or
    // duplicate parent and child disappearance handlers across recreation.
    let probe = StressLayoutLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL028", "Root"),
      size: .init(width: 42, height: 8)
    ) {
      StressLL028Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for _ in 1...8 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle Nested Lifecycle")
      #expect(probe.events == ["child disappear", "parent disappear"])
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle Nested Lifecycle")
      #expect(probe.events.filter { $0 == "child appear" }.count == 1)
      #expect(probe.events.filter { $0 == "parent appear" }.count == 1)
      #expect(harness.lifecycleRegistrationCount == 4)
    }
  }
}

@MainActor
private struct StressLL028Fixture: View {
  let probe: StressLayoutLifecycleProbe
  @State private var isVisible = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Nested Lifecycle") { isVisible.toggle() }
      if isVisible {
        VStack(alignment: .leading, spacing: 0) {
          Text("nested lifecycle child")
            .onAppear { probe.events.append("child appear") }
            .onDisappear { probe.events.append("child disappear") }
        }
        .onAppear { probe.events.append("parent appear") }
        .onDisappear { probe.events.append("parent disappear") }
      }
    }
  }
}

// MARK: - Attempt 029: opaque environment equality

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 029 non Equatable environment replacement invalidates reader")
  func stress029NonEquatableEnvironmentReplacementInvalidatesReader() throws {
    // Hypothesis: reflection-based equality may treat distinct non-Equatable
    // values as equal and incorrectly retain an EnvironmentReader subtree.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL029", "Root"),
      size: .init(width: 44, height: 8)
    ) {
      StressLL029Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Replace Opaque Environment")
      #expect(frame.contains("opaque environment payload \(generation)"))
    }
  }
}

private struct StressLL029OpaqueValue: Sendable, CustomDebugStringConvertible {
  var payload: Int

  var debugDescription: String { "opaque-environment-value" }
}

private enum StressLL029EnvironmentKey: EnvironmentKey {
  static let defaultValue = StressLL029OpaqueValue(payload: -1)
}

extension EnvironmentValues {
  fileprivate var stressLL029OpaqueValue: StressLL029OpaqueValue {
    get { self[StressLL029EnvironmentKey.self] }
    set { self[StressLL029EnvironmentKey.self] = newValue }
  }
}

@MainActor
private struct StressLL029Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Opaque Environment") { generation += 1 }
      EnvironmentReader(\.stressLL029OpaqueValue) { value in
        Text("opaque environment payload \(value.payload)")
      }
      .environment(
        \.stressLL029OpaqueValue,
        StressLL029OpaqueValue(payload: generation)
      )
    }
  }
}

// MARK: - Attempt 030: live environment in active sheet

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 030 active sheet reads current root environment")
  func stress030ActiveSheetReadsCurrentRootEnvironment() throws {
    // Hypothesis: a portal attachment payload may resolve under the environment
    // snapshot captured when the sheet first opened.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL030", "Root"),
      size: .init(width: 48, height: 10)
    ) {
      StressLL030Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Environment Sheet")
    for generation in 1...8 {
      let frame = try harness.clickText("Advance Root Environment", chooseLast: true)
      #expect(frame.contains("sheet environment \(generation)"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

private enum StressLL030EnvironmentKey: EnvironmentKey {
  static let defaultValue = -1
}

extension EnvironmentValues {
  fileprivate var stressLL030Value: Int {
    get { self[StressLL030EnvironmentKey.self] }
    set { self[StressLL030EnvironmentKey.self] = newValue }
  }
}

@MainActor
private struct StressLL030Fixture: View {
  @State private var generation = 0
  @State private var isPresented = false

  var body: some View {
    Button("Open Environment Sheet") { isPresented = true }
      .sheet("Environment", isPresented: $isPresented) {
        StressLL030Sheet(generation: $generation)
      }
      .environment(\.stressLL030Value, generation)
  }
}

@MainActor
private struct StressLL030Sheet: View {
  @Binding var generation: Int
  @Environment(\.stressLL030Value) private var environmentValue

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sheet environment \(environmentValue)")
      Button("Advance Root Environment") { generation += 1 }
    }
  }
}

// MARK: - Attempt 031: stacked value-animation bookkeeping

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 031 stacked value animations keep independent baselines")
  func stress031StackedValueAnimationsKeepIndependentBaselines() throws {
    // Hypothesis: multiple value-gated animation modifiers on one view may
    // alias the same retained previous-value slot and manufacture a change on
    // every otherwise identical resolve.
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("StressLL031", "Root")
    let proposal = ProposedSize(width: 32, height: 4)

    _ = renderer.render(
      stressLL031Fixture(),
      context: .init(identity: rootIdentity),
      proposal: proposal
    )

    for _ in 1...8 {
      let artifacts = renderer.render(
        stressLL031Fixture(),
        context: .init(identity: rootIdentity),
        proposal: proposal
      )
      let textNode = try #require(
        artifacts.resolvedTree.stressLLDescendant(withText: "stacked value animation probe")
      )
      #expect(textNode.transactionSnapshot.animationRequest == .inherit)
    }
  }
}

@MainActor
private func stressLL031Fixture() -> some View {
  Text("stacked value animation probe")
    .animation(.linear(duration: .milliseconds(120)), value: 1)
    .animation(.easeInOut(duration: .milliseconds(240)), value: 2)
}

extension ResolvedNode {
  fileprivate func stressLLDescendant(withText text: String) -> ResolvedNode? {
    if case .text(let value) = drawPayload, value == text {
      return self
    }

    for child in children {
      if let match = child.stressLLDescendant(withText: text) {
        return match
      }
    }

    return nil
  }
}

// MARK: - Attempt 032: transition resurrection

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 032 rapid reinsertion cancels the matching removal overlay")
  func stress032RapidReinsertionCancelsMatchingRemovalOverlay() throws {
    // Hypothesis: a same-identity insertion that races its in-flight removal
    // may leave the captured removal subtree alive beside the current subtree.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL032", "Root"),
      size: .init(width: 46, height: 8)
    ) {
      StressLL032Fixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      for _ in 1...8 {
        _ = try harness.clickText("Toggle Transition Resurrection")
        #expect(!controller.debugStateSnapshot().removingIdentities.isEmpty)

        let frame = try harness.clickText("Toggle Transition Resurrection")
        let occurrences =
          frame.components(separatedBy: "transition resurrection probe").count - 1
        #expect(occurrences == 1)
        #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
        #expect(controller.activeAnimationCount <= 1)
      }
    }
  }
}

@MainActor
private struct StressLL032Fixture: View {
  @State private var isVisible = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Transition Resurrection") {
        withAnimation(.linear(duration: .milliseconds(500))) {
          isVisible.toggle()
        }
      }
      if isVisible {
        Text("transition resurrection probe")
          .id("transition-resurrection-probe")
          .transition(.opacity)
      }
    }
  }
}

// MARK: - Attempt 033: repeat-forever sheet teardown

extension FrameworkStressLayoutLifecycleTests {
  @Test("stress 033 dismissing a sheet reclaims its repeat forever animation")
  func stress033DismissingSheetReclaimsRepeatForeverAnimation() throws {
    // Hypothesis: a portal subtree may disappear outside the ordinary child
    // diff and strand repeat-forever entries owned by its departed identities.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressLL033", "Root"),
      size: .init(width: 48, height: 14)
    ) {
      StressLL033Fixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      for _ in 1...8 {
        let shownFrame = try harness.clickText("Open Forever Sheet")
        #expect(shownFrame.contains("sheet repeat forever probe"))
        #expect(controller.activeAnimationCount > 0)

        let dismissedFrame = try harness.clickText("Close Forever Sheet", chooseLast: true)
        #expect(!dismissedFrame.contains("sheet repeat forever probe"))
        #expect(controller.activeAnimationCount == 0)
        #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
      }
    }
  }
}

@MainActor
private struct StressLL033Fixture: View {
  @State private var isPresented = false

  var body: some View {
    Button("Open Forever Sheet") { isPresented = true }
      .sheet("Forever", isPresented: $isPresented) {
        StressLL033Sheet(isPresented: $isPresented)
      }
  }
}

@MainActor
private struct StressLL033Sheet: View {
  @Binding var isPresented: Bool
  @State private var phase: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sheet repeat forever probe")
        .padding(1)
        .frame(width: 32, height: 3)
        .border(
          blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red]),
          set: .rounded,
          phase: phase
        )
        .onAppear {
          withAnimation(
            .linear(duration: .milliseconds(3000))
              .repeatForever(autoreverses: false)
          ) {
            phase = 1
          }
        }
      Button("Close Forever Sheet") { isPresented = false }
    }
  }
}
