@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Builder-slot identity migration runtime", .serialized)
struct BuilderSlotIdentityMigrationRuntimeTests {
  @Test("multi-element conditional preserves trailing state")
  func multiElementConditionalPreservesTrailingState() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BuilderSlotRuntime", "ConditionalState"),
      size: .init(width: 48, height: 9)
    ) {
      BuilderSlotConditionalStateProbe()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Increment tail")
    #expect(frame.contains("Tail count 1"))
    frame = try harness.clickText("Expand prefix")
    #expect(frame.contains("Tail count 1"))
    frame = try harness.clickText("Collapse prefix")
    #expect(frame.contains("Tail count 1"))
  }

  @Test("buildArray cardinality preserves trailing state")
  func buildArrayCardinalityPreservesTrailingState() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BuilderSlotRuntime", "ArrayState"),
      size: .init(width: 48, height: 10)
    ) {
      BuilderSlotArrayStateProbe()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Increment array tail")
    #expect(frame.contains("Array tail count 1"))
    frame = try harness.clickText("Grow array")
    #expect(frame.contains("Array tail count 1"))
    frame = try harness.clickText("Shrink array")
    #expect(frame.contains("Array tail count 1"))
  }

  @Test("conditional cardinality preserves trailing focus identity")
  func conditionalCardinalityPreservesTrailingFocusIdentity() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BuilderSlotRuntime", "Focus"),
      size: .init(width: 48, height: 8)
    ) {
      BuilderSlotFocusProbe()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Focus tail")
    let initialFocus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    _ = try harness.pressKey(KeyPress(.character("r")))
    let expandedFocus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    let liveFocus = try harness.focusIdentity(forText: "Focus tail")

    #expect(expandedFocus == initialFocus)
    #expect(expandedFocus == liveFocus)
  }

  @Test("conditional cardinality preserves trailing lifecycle and task ownership")
  func conditionalCardinalityPreservesTrailingLifecycleAndTaskOwnership() throws {
    let recorder = BuilderSlotOwnershipRecorder()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BuilderSlotRuntime", "Ownership"),
      size: .init(width: 48, height: 8)
    ) {
      BuilderSlotOwnershipProbe(recorder: recorder)
    }
    defer { harness.shutdown() }

    #expect(recorder.appearCount == 1)
    let initialTaskDescriptorIDs =
      harness.runLoop.lifecycleCoordinator.activeTaskDescriptors.values
      .flatMap { $0.map(\.id) }
    #expect(initialTaskDescriptorIDs.count == 1)

    _ = try harness.clickText("Toggle ownership prefix")
    #expect(recorder.appearCount == 1)
    #expect(recorder.disappearCount == 0)
    let currentTaskDescriptorIDs =
      harness.runLoop.lifecycleCoordinator.activeTaskDescriptors.values
      .flatMap { $0.map(\.id) }
    #expect(currentTaskDescriptorIDs == initialTaskDescriptorIDs)
  }

  @Test("conditional cardinality does not transition a trailing sibling")
  func conditionalCardinalityDoesNotTransitionTrailingSibling() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BuilderSlotRuntime", "Transition"),
      size: .init(width: 48, height: 8)
    ) {
      BuilderSlotTransitionProbe()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Toggle transition prefix")
    #expect(
      harness.runLoop.renderer.internalAnimationController.debugStateSnapshot()
        .removingIdentities.isEmpty
    )
  }
}

@MainActor
private struct BuilderSlotConditionalStateProbe: View {
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(expanded ? "Collapse prefix" : "Expand prefix") {
        expanded.toggle()
      }
      if expanded {
        Text("prefix-0")
        Text("prefix-1")
      }
      BuilderSlotTailCounter(label: "Tail")
    }
  }
}

@MainActor
private struct BuilderSlotArrayStateProbe: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(count == 0 ? "Grow array" : "Shrink array") {
        count = count == 0 ? 3 : 0
      }
      for index in 0..<count {
        Text("array-\(index)")
      }
      BuilderSlotTailCounter(label: "Array tail")
    }
  }
}

@MainActor
private struct BuilderSlotTailCounter: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) count \(count)")
      Button("Increment \(label.lowercased())") { count += 1 }
    }
  }
}

@MainActor
private struct BuilderSlotFocusProbe: View {
  @State private var expanded = false
  @State private var text = "Focus tail"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if expanded {
        Text("focus-prefix-0")
        Text("focus-prefix-1")
      }
      TextField("Focus tail", text: $text)
        .onKeyPress(.character("r")) { _ in
          expanded.toggle()
          return .handled
        }
    }
  }
}

@MainActor
private final class BuilderSlotOwnershipRecorder {
  var appearCount = 0
  var disappearCount = 0
}

@MainActor
private struct BuilderSlotOwnershipProbe: View {
  let recorder: BuilderSlotOwnershipRecorder
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle ownership prefix") { expanded.toggle() }
      if expanded {
        Text("ownership-prefix-0")
        Text("ownership-prefix-1")
      }
      Text("Ownership tail")
        .onAppear { recorder.appearCount += 1 }
        .onDisappear { recorder.disappearCount += 1 }
        .task {
          await AsyncEvent().wait()
        }
    }
  }
}

@MainActor
private struct BuilderSlotTransitionProbe: View {
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle transition prefix") { expanded.toggle() }
      if expanded {
        Text("transition-prefix-0")
        Text("transition-prefix-1")
      }
      Text("Transition tail")
        .transition(.opacity)
    }
    .animation(.linear(duration: .seconds(60)), value: expanded)
  }
}
