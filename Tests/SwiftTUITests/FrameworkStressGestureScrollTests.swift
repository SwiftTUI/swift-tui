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

// MARK: - Attempt 008: minimum-distance replacement during drag

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 008 active drag adopts a reduced minimum distance")
  func gestureScroll008ActiveDragAdoptsReducedMinimumDistance() throws {
    // Hypothesis: the preserved primitive keeps its press-time threshold after
    // a hover-driven re-resolution authors a lower minimum distance.
    let changes = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll008Root"),
      size: .init(width: 46, height: 7)
    ) {
      GestureScroll008Fixture(changes: changes)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Threshold drag"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.movePointer(to: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 2, y: start.y))

    withKnownIssue("Active DragGesture retains its press-time minimum distance") {
      #expect(changes.value == 1)
    }
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 2, y: start.y))
  }
}

private struct GestureScroll008Fixture: View {
  let changes: GestureScrollBox<Int>
  @State private var minimumDistance = 8.0

  var body: some View {
    Text("Threshold drag")
      .frame(width: 24, height: 1, alignment: .leading)
      .onPointerHover { phase in
        if case .entered = phase {
          minimumDistance = 1
        }
      }
      .gesture(
        DragGesture(minimumDistance: minimumDistance)
          .onChanged { _ in changes.value += 1 }
      )
  }
}

// MARK: - Attempt 009: departed long-press deadline ownership

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 009 removed long press cannot fire its deadline")
  func gestureScroll009RemovedLongPressCannotFireDeadline() throws {
    // Hypothesis: an active recognizer preserved for frame churn may remain in
    // the deadline scan after its owning subtree is genuinely removed.
    let fires = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll009Root"),
      size: .init(width: 46, height: 7)
    ) {
      GestureScroll009Fixture(fires: fires)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Departing hold"))
    _ = try harness.sendMouse(.down(.primary), at: start)
    let removedFrame = try harness.movePointer(to: start)
    #expect(removedFrame.contains("Hold removed"))
    harness.runLoop.drainGestureDeadlines(at: .now().advanced(by: .seconds(2)))
    _ = try harness.render()

    withKnownIssue("A removed active long press remains deadline-eligible") {
      #expect(fires.value == 0)
      #expect(harness.gestureRecognizerCount == 0)
    }
  }
}

private struct GestureScroll009Fixture: View {
  let fires: GestureScrollBox<Int>
  @State private var removed = false

  var body: some View {
    if removed {
      Text("Hold removed")
    } else {
      Text("Departing hold")
        .frame(width: 24, height: 1, alignment: .leading)
        .onPointerHover { phase in
          if case .entered = phase {
            removed = true
          }
        }
        .onLongPressGesture(minimumDuration: .seconds(1)) {
          fires.value += 1
        }
    }
  }
}

// MARK: - Attempt 010: multi-tap count replacement

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 010 partial tap sequence adopts a new required count")
  func gestureScroll010PartialTapSequenceAdoptsNewRequiredCount() throws {
    // Hypothesis: preserving a partial multi-tap recognizer retains its old
    // required count when the same attachment is re-authored between taps.
    let fires = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll010Root"),
      size: .init(width: 48, height: 7)
    ) {
      GestureScroll010Fixture(fires: fires)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Retuned multi tap"))
    _ = try harness.click(point)
    _ = try harness.movePointer(to: point)
    _ = try harness.click(point)

    withKnownIssue("A partial TapGesture retains its original required count") {
      #expect(fires.value == 1)
    }
  }
}

private struct GestureScroll010Fixture: View {
  let fires: GestureScrollBox<Int>
  @State private var requiredCount = 3

  var body: some View {
    Text("Retuned multi tap")
      .frame(width: 26, height: 1, alignment: .leading)
      .onPointerHover { phase in
        if case .entered = phase {
          requiredCount = 2
        }
      }
      .gesture(
        TapGesture(count: requiredCount)
          .onEnded { fires.value += 1 }
      )
  }
}

// MARK: - Attempt 011: hover callback rebinding

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 011 hover continuation uses the reauthored callback")
  func gestureScroll011HoverContinuationUsesReauthoredCallback() throws {
    // Hypothesis: replacing a hover callback at a stable identity may either
    // retain the old closure or fabricate a second enter instead of continuing.
    let events = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll011Root"),
      size: .init(width: 48, height: 7)
    ) {
      GestureScroll011Fixture(events: events)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Rebound hover"))
    _ = try harness.movePointer(to: point)
    _ = try harness.movePointer(to: Point(x: point.x + 1, y: point.y))

    withKnownIssue("Replacing a hovered callback fabricates a second enter") {
      #expect(events.value == ["old-enter", "new-move"])
    }
    #expect(harness.pointerHoverHandlerCount == 1)
  }
}

private struct GestureScroll011Fixture: View {
  static let identity = testIdentity("GestureScroll011", "Target")

  let events: GestureScrollBox<[String]>
  @State private var generation = 0

  var body: some View {
    if generation == 0 {
      Text("Rebound hover")
        .id(Self.identity)
        .frame(width: 26, height: 1, alignment: .leading)
        .onPointerHover { phase in
          if case .entered = phase {
            events.value.append("old-enter")
            generation = 1
          }
        }
    } else {
      Text("Rebound hover")
        .id(Self.identity)
        .frame(width: 26, height: 1, alignment: .leading)
        .onPointerHover { phase in
          switch phase {
          case .entered:
            events.value.append("new-enter")
          case .moved:
            events.value.append("new-move")
          case .exited:
            events.value.append("new-exit")
          }
        }
    }
  }
}

// MARK: - Attempt 012: drop delivery inside an active hover

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 012 drop preserves hover continuity")
  func gestureScroll012DropPreservesHoverContinuity() throws {
    // Hypothesis: spatial drop routing may clear or re-key the active pointer
    // hover even though the pointer never left its hit region.
    let phases = GestureScrollBox<[String]>([])
    let drops = GestureScrollBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll012Root"),
      size: .init(width: 48, height: 8)
    ) {
      GestureScroll012Fixture(phases: phases, drops: drops)
    }
    defer { harness.shutdown() }

    let point = try #require(harness.point(forText: "Hover drop target"))
    _ = try harness.movePointer(to: point)
    _ = try harness.drop(
      paths: [DroppedPath("/tmp/gesture-scroll-012")],
      context: DropContext(location: point)
    )
    _ = try harness.movePointer(to: Point(x: point.x + 1, y: point.y))

    #expect(drops.value == 1)
    #expect(phases.value == ["entered", "moved"])
  }
}

private struct GestureScroll012Fixture: View {
  let phases: GestureScrollBox<[String]>
  let drops: GestureScrollBox<Int>

  var body: some View {
    Panel(id: "gesture-scroll-012-panel") {
      Text("Hover drop target")
        .frame(width: 26, height: 1, alignment: .leading)
        .focusable()
        .onPointerHover { phase in
          switch phase {
          case .entered: phases.value.append("entered")
          case .moved: phases.value.append("moved")
          case .exited: phases.value.append("exited")
          }
        }
    }
    .dropDestination { _ in
      drops.value += 1
      return true
    }
    .frame(width: 30, height: 4)
  }
}

// MARK: - Attempt 013: drop callback rebinding

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 013 stable drop scope uses its current callback")
  func gestureScroll013StableDropScopeUsesCurrentCallback() throws {
    // Hypothesis: snapshot restoration may reinstall the drop closure captured
    // before a stable Panel scope re-authors its destination.
    let destinations = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll013Root"),
      size: .init(width: 50, height: 9)
    ) {
      GestureScroll013Fixture(destinations: destinations)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget drop")
    let point = try #require(harness.point(forText: "Current drop target"))
    _ = try harness.drop(
      paths: [DroppedPath("/tmp/gesture-scroll-013")],
      context: DropContext(location: point)
    )

    #expect(destinations.value == ["second"])
    #expect(harness.dropDestinationRegistrationCount == 1)
  }
}

private struct GestureScroll013Fixture: View {
  let destinations: GestureScrollBox<[String]>
  @State private var targetsSecond = false

  var body: some View {
    if targetsSecond {
      Panel(id: "gesture-scroll-013-panel") {
        VStack(alignment: .leading, spacing: 0) {
          Button("Retarget drop") {}
          Text("Current drop target").focusable()
        }
      }
      .dropDestination { _ in
        destinations.value.append("second")
        return true
      }
      .frame(width: 32, height: 5)
    } else {
      Panel(id: "gesture-scroll-013-panel") {
        VStack(alignment: .leading, spacing: 0) {
          Button("Retarget drop") { targetsSecond = true }
          Text("Current drop target").focusable()
        }
      }
      .dropDestination { _ in
        destinations.value.append("first")
        return true
      }
      .frame(width: 32, height: 5)
    }
  }
}

// MARK: - Attempt 014: nested drop-destination removal

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 014 removed inner drop destination bubbles only to outer")
  func gestureScroll014RemovedInnerDropDestinationBubblesOnlyToOuter() throws {
    // Hypothesis: removing one nested destination may leave its snapshot entry
    // on the spatial scope path ahead of the still-live outer destination.
    let destinations = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll014Root"),
      size: .init(width: 54, height: 11)
    ) {
      GestureScroll014Fixture(destinations: destinations)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Remove inner destination")
    let point = try #require(harness.point(forText: "Nested drop leaf"))
    _ = try harness.drop(
      paths: [DroppedPath("/tmp/gesture-scroll-014")],
      context: DropContext(location: point)
    )

    #expect(destinations.value == ["outer"])
    #expect(harness.dropDestinationRegistrationCount == 1)
  }
}

private struct GestureScroll014Fixture: View {
  let destinations: GestureScrollBox<[String]>
  @State private var includesInner = true

  var body: some View {
    Panel(id: "gesture-scroll-014-outer") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Remove inner destination") { includesInner = false }
        if includesInner {
          Panel(id: "gesture-scroll-014-inner") {
            Text("Nested drop leaf").focusable()
          }
          .dropDestination { _ in
            destinations.value.append("retired-inner")
            return true
          }
        } else {
          Panel(id: "gesture-scroll-014-inner") {
            Text("Nested drop leaf").focusable()
          }
        }
      }
    }
    .dropDestination { _ in
      destinations.value.append("outer")
      return true
    }
    .frame(width: 38, height: 7)
  }
}

// MARK: - Attempt 015: hover and captured drag coexistence

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 015 hover subscription coexists with captured drag")
  func gestureScroll015HoverSubscriptionCoexistsWithCapturedDrag() throws {
    // Hypothesis: a hover route at the same identity may replace or intercept
    // the capturing drag's primary pointer handler during dispatch.
    let hoverPhases = GestureScrollBox<[String]>([])
    let dragEvents = GestureScrollBox<[String]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll015Root"),
      size: .init(width: 50, height: 8)
    ) {
      GestureScroll015Fixture(hoverPhases: hoverPhases, dragEvents: dragEvents)
    }
    defer { harness.shutdown() }

    let start = try #require(harness.point(forText: "Hover drag target"))
    _ = try harness.movePointer(to: start)
    _ = try harness.sendMouse(.down(.primary), at: start)
    _ = try harness.sendMouse(.dragged(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.sendMouse(.up(.primary), at: Point(x: start.x + 3, y: start.y))
    _ = try harness.movePointer(to: Point(x: 48, y: 7))

    #expect(dragEvents.value == ["changed", "changed", "changed", "ended"])
    #expect(hoverPhases.value == ["entered", "exited"])
  }
}

private struct GestureScroll015Fixture: View {
  let hoverPhases: GestureScrollBox<[String]>
  let dragEvents: GestureScrollBox<[String]>

  var body: some View {
    Text("Hover drag target")
      .frame(width: 26, height: 1, alignment: .leading)
      .onPointerHover { phase in
        switch phase {
        case .entered: hoverPhases.value.append("entered")
        case .moved: break
        case .exited: hoverPhases.value.append("exited")
        }
      }
      .gesture(
        DragGesture()
          .onChanged { _ in dragEvents.value.append("changed") }
          .onEnded { _ in dragEvents.value.append("ended") }
      )
  }
}

// MARK: - Attempt 016: successive anchor changes

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 016 successive scroll anchors use live geometry")
  func gestureScroll016SuccessiveScrollAnchorsUseLiveGeometry() throws {
    // Hypothesis: a second command for the same target may reuse its pre-scroll
    // rect, compounding the first anchor delta instead of realigning from live geometry.
    let position = GestureScrollBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll016Root"),
      size: .init(width: 48, height: 9)
    ) {
      GestureScroll016Fixture(position: position)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Target to top")
    #expect(position.value.y == 8)
    _ = try harness.clickText("Target to bottom")
    #expect(position.value.y == 5)
  }
}

private struct GestureScroll016Fixture: View {
  let position: GestureScrollBox<ScrollPosition>

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Target to top") { _ = proxy.scrollTo("anchor-target", anchor: .top) }
          Button("Target to bottom") { _ = proxy.scrollTo("anchor-target", anchor: .bottom) }
        }
        ScrollView(.vertical, showsIndicators: false, position: position.binding()) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12) { row in
              Text("Anchor row \(row)")
                .id(row == 8 ? "anchor-target" : "anchor-row-\(row)")
            }
          }
        }
        .frame(width: 28, height: 4, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 017: target relocation between commands

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 017 relocated target replaces its old scroll rect")
  func gestureScroll017RelocatedTargetReplacesOldScrollRect() throws {
    // Hypothesis: a stable explicit target ID may retain its old placement
    // after moving earlier in the collection, sending the next command downward.
    let position = GestureScrollBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll017Root"),
      size: .init(width: 48, height: 9)
    ) {
      GestureScroll017Fixture(position: position)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reveal moving target")
    #expect(position.value.y == 6)
    _ = try harness.clickText("Move target earlier")
    _ = try harness.clickText("Reveal moving target")

    #expect(position.value.y == 0)
  }
}

private struct GestureScroll017Fixture: View {
  let position: GestureScrollBox<ScrollPosition>
  @State private var targetRow = 9

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Move target earlier") { targetRow = 2 }
          Button("Reveal moving target") {
            _ = proxy.scrollTo("moving-target", anchor: .bottom)
          }
        }
        ScrollView(.vertical, showsIndicators: false, position: position.binding()) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12) { row in
              Text("Moving target row \(row)")
                .id(row == targetRow ? "moving-target" : "moving-row-\(row)")
            }
          }
        }
        .frame(width: 30, height: 4, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 018: duplicate IDs in sibling reader scopes

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 018 duplicate target IDs stay reader scoped")
  func gestureScroll018DuplicateTargetIDsStayReaderScoped() throws {
    // Hypothesis: global target publication may let a sibling reader command
    // select the first matching explicit ID outside the reader's identity scope.
    let first = GestureScrollBox(ScrollPosition.zero)
    let second = GestureScrollBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll018Root"),
      size: .init(width: 52, height: 13)
    ) {
      GestureScroll018Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reveal second duplicate")

    #expect(first.value == .zero)
    #expect(second.value.y == 6)
  }
}

private struct GestureScroll018Fixture: View {
  let first: GestureScrollBox<ScrollPosition>
  let second: GestureScrollBox<ScrollPosition>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GestureScroll018Reader(label: "first", position: first)
      GestureScroll018Reader(label: "second", position: second)
    }
  }
}

private struct GestureScroll018Reader: View {
  let label: String
  let position: GestureScrollBox<ScrollPosition>

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Reveal \(label) duplicate") {
          _ = proxy.scrollTo("duplicate-target", anchor: .bottom)
        }
        ScrollView(.vertical, showsIndicators: false, position: position.binding()) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<10) { row in
              Text("\(label) duplicate row \(row)")
                .id(row == 8 ? "duplicate-target" : "\(label)-row-\(row)")
            }
          }
        }
        .frame(width: 30, height: 3, alignment: .topLeading)
      }
    }
  }
}

// MARK: - Attempt 019: reader command after position-binding replacement

extension FrameworkStressGestureScrollTests {
  @Test("stress gesture scroll 019 reader command writes only the current binding")
  func gestureScroll019ReaderCommandWritesOnlyCurrentBinding() throws {
    // Hypothesis: ScrollViewReader may retain the registration closure for
    // binding A after a stable ScrollView is re-authored against binding B.
    let first = GestureScrollBox(ScrollPosition.zero)
    let second = GestureScrollBox(ScrollPosition.zero)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureScroll019Root"),
      size: .init(width: 48, height: 9)
    ) {
      GestureScroll019Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Switch reader binding")
    _ = try harness.clickText("Reader to bottom")

    #expect(first.value == .zero)
    #expect(harness.scrollPositionRegistrationCount == 1)
    withKnownIssue("Reader commands lose the current binding after replacement") {
      #expect(second.value.y == 9)
    }
  }
}

private struct GestureScroll019Fixture: View {
  static let scrollIdentity = testIdentity("GestureScroll019", "Scroll")

  let first: GestureScrollBox<ScrollPosition>
  let second: GestureScrollBox<ScrollPosition>
  @State private var usesSecond = false

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Switch reader binding") { usesSecond = true }
          Button("Reader to bottom") { _ = proxy.scrollTo(edge: .bottom) }
        }
        ScrollView(
          .vertical,
          showsIndicators: false,
          position: usesSecond ? second.binding() : first.binding()
        ) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12) { row in Text("Reader binding row \(row)") }
          }
        }
        .id(Self.scrollIdentity)
        .frame(width: 30, height: 3, alignment: .topLeading)
      }
    }
  }
}
