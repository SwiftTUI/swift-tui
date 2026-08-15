import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A registration authored at an `Equatable` memo boundary's own identity is
/// recorded on the boundary node, and that node is then absorbed into its
/// parent (the chain-collapse stamp fixed point) — `adoptRuntimeRegistrations`
/// moves the record onto a live node.
///
/// The record's owner key had to move with it. The registries restore owner
/// keys verbatim from the record, and their owner-liveness passes
/// (`prune(keeping:)`) prove departure from the key's `viewNodeID` alone — so
/// an adopted entry still naming the absorbed node was torn down on the next
/// pass even though a live node carried its record. The gesture reached its
/// resolve, registered, and was pruned before the first event.
///
/// The shape matters: the attachment must be the memo boundary body's ROOT, so
/// its identity collapses onto the boundary node. Wrapping the body in a
/// container gives the attachment its own live node and hides the defect.
@MainActor
@Suite(.serialized)
struct MemoBoundaryRegistrationAdoptionTests {
  @Test("a gesture at an Equatable boundary's body root survives publication")
  func gestureAtBoundaryRootSurvivesPublication() throws {
    let events = MemoBoundaryEventLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MemoBoundaryGestureRoot"),
      size: .init(width: 48, height: 8)
    ) {
      MemoBoundaryGestureFixture(events: events)
    }
    defer { harness.shutdown() }

    // The recognizer must still be registered after the publication that
    // follows the resolve which authored it.
    #expect(harness.gestureRecognizerCount == 1)

    _ = try harness.clickText("boundary gesture target")
    #expect(events.value == ["boundary-high"])
  }

  /// Control: the same attachment one container below the boundary keeps its
  /// own live node, so it never depended on the adoption re-homing. Pins that
  /// the fix did not simply move the failure.
  @Test("a gesture below an Equatable boundary's body root also survives")
  func gestureBelowBoundaryRootSurvivesPublication() throws {
    let events = MemoBoundaryEventLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MemoBoundaryNestedRoot"),
      size: .init(width: 48, height: 8)
    ) {
      MemoBoundaryNestedGestureFixture(events: events)
    }
    defer { harness.shutdown() }

    #expect(harness.gestureRecognizerCount == 1)
    _ = try harness.clickText("boundary gesture target")
    #expect(events.value == ["boundary-high"])
  }
}

@MainActor
final class MemoBoundaryEventLog {
  var value: [String] = []
  init() {}
}

private struct MemoBoundaryGestureBody: View {
  let events: MemoBoundaryEventLog

  var body: some View {
    Text("boundary gesture target")
      .frame(width: 30, height: 1, alignment: .leading)
      .highPriorityGesture(
        TapGesture().onEnded { events.value.append("boundary-high") }
      )
  }
}

private struct MemoBoundaryGestureChild: View, Equatable {
  let events: MemoBoundaryEventLog

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.events === rhs.events
  }

  var body: some View {
    MemoBoundaryGestureBody(events: events)
  }
}

private struct MemoBoundaryGestureFixture: View {
  let events: MemoBoundaryEventLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MemoBoundaryGestureChild(events: events)
        .equatable()
    }
  }
}

private struct MemoBoundaryNestedGestureBody: View {
  let events: MemoBoundaryEventLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("boundary gesture target")
        .frame(width: 30, height: 1, alignment: .leading)
        .highPriorityGesture(
          TapGesture().onEnded { events.value.append("boundary-high") }
        )
    }
  }
}

private struct MemoBoundaryNestedGestureChild: View, Equatable {
  let events: MemoBoundaryEventLog

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.events === rhs.events
  }

  var body: some View {
    MemoBoundaryNestedGestureBody(events: events)
  }
}

private struct MemoBoundaryNestedGestureFixture: View {
  let events: MemoBoundaryEventLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MemoBoundaryNestedGestureChild(events: events)
        .equatable()
    }
  }
}
