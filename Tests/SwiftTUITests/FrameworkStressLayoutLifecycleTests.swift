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
