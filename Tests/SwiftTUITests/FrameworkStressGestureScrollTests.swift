import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI gesture and scroll stress behavior", .serialized)
struct FrameworkStressGestureScrollTests {}

@MainActor
private final class GestureScrollBox<Value> {
  var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: { self.value = $0 }
    )
  }
}

// MARK: - Attempt 001: live gesture-mask removal

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 001 removing a gesture mask retires its route")
  func gestureScroll001RemovingGestureMaskRetiresRoute() throws {
    // Hypothesis: replayed pointer registrations may keep a recognizer alive
    // after a stable attachment changes its mask from `.all` to `.none`.
    let taps = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll001Root"),
      size: .init(width: 42, height: 7)
    ) {
      GestureScroll001Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Masked target")
    _ = try harness.clickText("Disable gesture")
    _ = try harness.clickText("Masked target")

    #expect(taps.value == 1)
    #expect(harness.gestureRecognizerCount == 0)
  }
}

private struct GestureScroll001Fixture: View {
  let taps: GestureScrollBox<Int>
  @State private var enabled = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Disable gesture") { enabled = false }
      Text("Masked target")
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          TapGesture().onEnded { taps.value += 1 },
          including: enabled ? .all : .none
        )
    }
  }
}

// MARK: - Attempt 002: live gesture-mask installation

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 002 enabling a gesture mask installs its route once")
  func gestureScroll002EnablingGestureMaskInstallsRouteOnce() throws {
    // Hypothesis: a cacheable attachment first resolved with `.none` may never
    // publish its recognizer when the same node later changes to `.all`.
    let taps = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll002Root"),
      size: .init(width: 42, height: 7)
    ) {
      GestureScroll002Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Dormant target")
    _ = try harness.clickText("Enable gesture")
    _ = try harness.clickText("Dormant target")
    _ = try harness.clickText("Dormant target")

    #expect(taps.value == 2)
    #expect(harness.gestureRecognizerCount == 1)
  }
}

private struct GestureScroll002Fixture: View {
  let taps: GestureScrollBox<Int>
  @State private var enabled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Enable gesture") { enabled = true }
      Text("Dormant target")
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          TapGesture().onEnded { taps.value += 1 },
          including: enabled ? .all : .none
        )
    }
  }
}

// MARK: - Attempt 003: subview-only gesture mask

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 003 subviews mask excludes only the attached gesture")
  func gestureScroll003SubviewsMaskExcludesOnlyAttachedGesture() throws {
    // Hypothesis: short-circuiting a `.subviews` attachment may accidentally
    // suppress recognizers that its already-resolved content contributed.
    let events = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll003Root"),
      size: .init(width: 42, height: 7)
    ) {
      GestureScroll003Fixture(events: events)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Subview gesture")

    #expect(events.value == ["child"])
    #expect(harness.gestureRecognizerCount == 1)
  }
}

private struct GestureScroll003Fixture: View {
  let events: GestureScrollBox<[String]>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Subview gesture")
        .frame(width: 24, height: 1, alignment: .leading)
        .onTapGesture { events.value.append("child") }
    }
    .gesture(
      TapGesture().onEnded { events.value.append("parent") },
      including: .subviews
    )
  }
}

// MARK: - Attempt 004: gesture-only mask versus descendant

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 004 gesture mask suppresses descendant recognizers")
  func gestureScroll004GestureMaskSuppressesDescendantRecognizers() throws {
    // Hypothesis: `.gesture` may be treated only as an attachment-local flag,
    // allowing a descendant recognizer to consume the event it should exclude.
    let events = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll004Root"),
      size: .init(width: 42, height: 7)
    ) {
      GestureScroll004Fixture(events: events)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Exclusive parent gesture")

    withKnownIssue("GestureMask.gesture does not suppress descendant recognizers") {
      #expect(events.value == ["parent"])
    }
  }
}

private struct GestureScroll004Fixture: View {
  let events: GestureScrollBox<[String]>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Exclusive parent gesture")
        .frame(width: 28, height: 1, alignment: .leading)
        .onTapGesture { events.value.append("child") }
    }
    .gesture(
      TapGesture().onEnded { events.value.append("parent") },
      including: .gesture
    )
  }
}

// MARK: - Attempt 005: stacked gesture removal during capture

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 005 removing a stacked gesture during drag is durable")
  func gestureScroll005RemovingStackedGestureDuringDragIsDurable() throws {
    // Hypothesis: positional preservation of an active drag may also restore a
    // departed sibling recognizer after the interaction terminates.
    let taps = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll005Root"),
      size: .init(width: 44, height: 7)
    ) {
      GestureScroll005Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Shrinking gesture stack"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.clickText("Shrinking gesture stack")

    #expect(taps.value == 0)
    #expect(harness.gestureRecognizerCount == 1)
  }
}

private struct GestureScroll005Fixture: View {
  static let identity = testIdentity("GestureScroll005", "Target")

  let taps: GestureScrollBox<Int>
  @State private var includesTap = true

  var body: some View {
    if includesTap {
      Text("Shrinking gesture stack")
        .id(Self.identity)
        .frame(width: 28, height: 1, alignment: .leading)
        .gesture(
          DragGesture().onChanged { _ in includesTap = false }
        )
        .onTapGesture { taps.value += 1 }
    } else {
      Text("Shrinking gesture stack")
        .id(Self.identity)
        .frame(width: 28, height: 1, alignment: .leading)
        .gesture(DragGesture().onChanged { _ in })
    }
  }
}

// MARK: - Attempt 006: primitive gesture shape replacement

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 006 replacing tap with long press drops tap semantics")
  func gestureScroll006ReplacingTapWithLongPressDropsTapSemantics() throws {
    // Hypothesis: stable-identity route replay may retain the old non-capturing
    // tap recognizer when the authored primitive changes to a long press.
    let taps = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll006Root"),
      size: .init(width: 46, height: 7)
    ) {
      GestureScroll006Fixture(taps: taps)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Use long press")
    _ = try harness.clickText("Shape changing gesture")

    #expect(taps.value == 0)
    #expect(harness.gestureRecognizerCount == 1)
  }
}

private struct GestureScroll006Fixture: View {
  static let identity = testIdentity("GestureScroll006", "Target")

  let taps: GestureScrollBox<Int>
  @State private var usesLongPress = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Use long press") { usesLongPress = true }
      if usesLongPress {
        Text("Shape changing gesture")
          .id(Self.identity)
          .frame(width: 28, height: 1, alignment: .leading)
          .onLongPressGesture(minimumDuration: .seconds(2)) {}
      } else {
        Text("Shape changing gesture")
          .id(Self.identity)
          .frame(width: 28, height: 1, alignment: .leading)
          .onTapGesture { taps.value += 1 }
      }
    }
  }
}

// MARK: - Attempt 007: coordinate-space replacement during drag

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 007 active drag adopts a new coordinate space")
  func gestureScroll007ActiveDragAdoptsNewCoordinateSpace() throws {
    // Hypothesis: preserving an active primitive across re-resolution keeps
    // the coordinate space captured at press time even after it is re-authored.
    let values = GestureScrollBox<[DragGesture.Value]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll007Root"),
      size: .init(width: 50, height: 7)
    ) {
      GestureScroll007Fixture(values: values)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Coordinate drag"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 2, y: start.y))
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 4, y: start.y))
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 4, y: start.y))

    let latest = try #require(values.value.last)
    let expectedGlobal = Point(
      x: floor(start.x + 4) + 0.5,
      y: floor(start.y) + 0.5
    )
    withKnownIssue("An active DragGesture retains its original coordinate space") {
      #expect(latest.location == expectedGlobal)
    }
  }
}

private struct GestureScroll007Fixture: View {
  let values: GestureScrollBox<[DragGesture.Value]>
  @State private var usesGlobal = false

  var body: some View {
    HStack(spacing: 0) {
      Text("prefix:")
      Text("Coordinate drag")
        .frame(width: 24, height: 1, alignment: .leading)
        .gesture(
          DragGesture(coordinateSpace: usesGlobal ? .global : .local)
            .onChanged { value in
              values.value.append(value)
              usesGlobal = true
            }
        )
    }
  }
}
