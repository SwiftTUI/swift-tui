import SwiftTUICore
import Testing

@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A selective (dirty-frontier) frame re-evaluates the nodes a state write
/// invalidated and serves their ancestors from committed snapshots. When a
/// re-evaluated node commits a different preference output, an ancestor
/// that consumes preferences in its own resolve — a `NavigationStack`
/// reading destination declarations, an `overlayPreferenceValue` above a
/// `transformPreference` — was stale until the next root frame: a
/// `navigationDestination(isPresented:)` push whose write invalidated only
/// the modifier rendered nothing, in the synchronous and the asynchronous
/// driver alike (org task T173). The frame head now escalates such a frame
/// to the root evaluator (`nil_preference_delta`), so the frame costs a root
/// frame exactly when a resolve-time preference changed.
@MainActor
@Suite(.serialized)
struct SelectivePreferenceRippleTests {
  @Test("a navigationDestination(isPresented:) push renders on the write's own selective frame")
  func navigationPushRendersSelectively() throws {
    let rootIdentity = testIdentity("RippleNavRoot")
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 44, height: 9),
      selectiveEvaluation: true
    ) {
      RippleNavigationFixture()
    }
    defer { harness.shutdown() }

    let frame = try harness.clickText("Open Fresh Destination")
    #expect(frame.contains("fresh local 0"), "the pushed destination did not render:\n\(frame)")
    try expectPreferenceDeltaEscalation(harness, changedAt: "RippleNavRoot/Root")

    let incremented = try harness.clickText("Increment Fresh Local")
    #expect(
      incremented.contains("fresh local 1"), "destination state did not render:\n\(incremented)")

    let closed = try harness.clickText("Close Fresh Destination")
    #expect(!closed.contains("fresh local"), "the popped destination is still rendered:\n\(closed)")
    #expect(closed.contains("Open Fresh Destination"), "the root did not return:\n\(closed)")
  }

  @Test("a transformPreference reading changed state reaches the consumer above the frontier")
  func transformPreferenceRipplesToItsConsumer() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RipplePreferenceRoot"),
      size: .init(width: 62, height: 7),
      selectiveEvaluation: true
    ) {
      RipplePreferenceFixture()
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("values [1, 0]"), "initial frame:\n\(harness.frame)")

    for generation in 1...4 {
      let frame = try harness.clickText("Advance")
      #expect(
        frame.contains("values [1, \(generation)]"),
        "the consumer above the frontier rendered a stale payload at generation \(generation):\n\(frame)"
      )
      try expectPreferenceDeltaEscalation(harness, changedAt: "RipplePreferenceRoot/VStack[1]")
    }
  }
}

extension SelectivePreferenceRippleTests {
  @Test("a served stack keeps its pop chain, so Escape pops the focused sibling")
  func servedStackKeepsItsPopChain() throws {
    // Two stacks present destinations from the first frame. Focusing a
    // destination target is a selective frame beneath both stacks; the
    // snapshot rebuild above the frontier used to re-derive each stack's
    // preferences from its children, dropping the pop chain the stack's
    // body had published — Escape then found no pop action at all.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RippleSiblingRoot"),
      size: .init(width: 72, height: 9),
      selectiveEvaluation: true
    ) {
      RippleSiblingStacksFixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Right Destination Target")
    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Left Destination Target"), "the unfocused sibling popped:\n\(frame)")
    #expect(frame.contains("Right Root Target"), "the focused stack did not pop:\n\(frame)")
    #expect(
      !frame.contains("Right Destination Target"), "the focused destination stayed:\n\(frame)")

    _ = try harness.focusText("Left Destination Target")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Left Root Target"), "the left stack did not pop:\n\(frame)")
    #expect(!frame.contains("Left Destination Target"), "the left destination stayed:\n\(frame)")
  }
}

// MARK: - Support

/// The frame just rendered escalated to the root evaluator BECAUSE a
/// frontier evaluation committed a changed preference output — the content
/// rendered for the right reason, not through an unrelated root cause such
/// as a focus move — and the node at `changedAt` was among the changed ones
/// (the frontier may also contain its ancestors, which then report the
/// escalation themselves).
@MainActor
private func expectPreferenceDeltaEscalation<V: View>(
  _ harness: StressRuntimeHarness<V>,
  changedAt identityPath: String
) throws {
  let notes = harness.runLoop.renderer.viewGraph.preferenceDeltaNotesThisFrame
  #expect(
    notes.contains { $0.contains("-> root escalation") },
    "no preference delta escalation: \(notes)"
  )
  #expect(
    notes.contains { $0.hasPrefix("changed \(identityPath)") },
    "the frontier never committed a changed preference at \(identityPath): \(notes)"
  )
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  let evaluatedPaths = graph.evaluatedNodeIDsThisFrame.compactMap {
    graph.identityByNodeID[$0]?.path
  }
  #expect(
    evaluatedPaths.contains { $0.hasPrefix("__TerminalUIPortalHost") },
    "the escalation did not reach the root evaluator: \(evaluatedPaths.sorted())"
  )
}

private struct RippleSiblingStacksFixture: View {
  @State private var left = true
  @State private var right = true

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      NavigationStack {
        Button("Left Root Target") { left = true }
          .navigationDestination(isPresented: $left) {
            Button("Left Destination Target") {}
          }
      }
      NavigationStack {
        Button("Right Root Target") { right = true }
          .navigationDestination(isPresented: $right) {
            Button("Right Destination Target") {}
          }
      }
    }
  }
}

private struct RippleNavigationFixture: View {
  @State private var isPresented = false

  var body: some View {
    NavigationStack {
      Button("Open Fresh Destination") { isPresented = true }
        .navigationDestination(isPresented: $isPresented) {
          RippleNavigationDestination(isPresented: $isPresented)
        }
    }
  }
}

@MainActor
private struct RippleNavigationDestination: View {
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

private enum RippleListPreferenceKey: PreferenceKey {
  static let defaultValue: [Int] = []

  static func reduce(value: inout [Int], nextValue: () -> [Int]) {
    value.append(contentsOf: nextValue())
  }
}

/// The observation-effects 016 shape: the transform closure reads state the
/// button writes, and the consumer sits two modifier levels above it.
private struct RipplePreferenceFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance") { generation += 1 }
      Text("source")
        .preference(key: RippleListPreferenceKey.self, value: [1])
        .transformPreference(RippleListPreferenceKey.self) { value in
          value.append(generation)
        }
        .frame(width: 58, height: 2, alignment: .topLeading)
        .overlayPreferenceValue(RippleListPreferenceKey.self, alignment: .bottomLeading) { value in
          Text("values \(value)")
        }
    }
  }
}
