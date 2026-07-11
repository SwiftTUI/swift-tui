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
