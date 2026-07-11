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
      withKnownIssue("The anchor overlay retains its first reminted source payload") {
        #expect(frame.contains("anchor x \(expectedX) generation \(generation)"))
      }
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
      withKnownIssue("An active sheet retains the payload captured one render earlier") {
        #expect(frame.contains("sheet version \(generation) local \(generation)"))
      }
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
