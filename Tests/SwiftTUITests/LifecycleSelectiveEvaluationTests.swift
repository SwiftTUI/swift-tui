import Observation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct LifecycleSelectiveEvaluationTests {
  @Test("selective child invalidation under transparent task owner preserves the task")
  func selectiveChildInvalidationUnderTransparentTaskOwnerPreservesTask() throws {
    let model = LifecycleSelectiveCounter()
    let invalidator = LifecycleSelectiveRecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let taskRegistry = LocalTaskRegistry()
    let renderer = DefaultRenderer()
    renderer.enableSelectiveEvaluation()
    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localTaskRegistry: taskRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      LifecycleSelectiveTransparentTaskProbe(model: model),
      context: initialContext
    )
    let initialNode = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Count 0")
    )
    let expectedTask = TaskDescriptor(
      id: "\(initialNode.identity)#task[\"stable\"]",
      priority: .userInitiated
    )
    #expect(initialNode.lifecycleMetadata.task == expectedTask)
    #expect(taskRegistry.registration(for: initialNode.identity)?.descriptor == expectedTask)

    invalidator.clear()
    model.count = 1
    let invalidated = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidated.isEmpty)
    #expect(!invalidated.contains(testIdentity("Root")))

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidated,
      localTaskRegistry: taskRegistry,
      applyEnvironmentValues: true
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      LifecycleSelectiveTransparentTaskProbe(model: model),
      context: updatedContext
    )
    let updatedNode = try #require(
      updatedArtifacts.resolvedTree.descendant(withText: "Count 1")
    )

    #expect(updatedNode.identity == initialNode.identity)
    #expect(updatedNode.lifecycleMetadata.task == expectedTask)
    #expect(taskRegistry.registration(for: updatedNode.identity)?.descriptor == expectedTask)
    #expect(updatedArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("selective child invalidation under transparent appear disappear owner preserves handlers")
  func selectiveChildInvalidationUnderTransparentAppearDisappearOwnerPreservesHandlers() throws {
    let model = LifecycleSelectiveCounter()
    let invalidator = LifecycleSelectiveRecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let lifecycleRegistry = LocalLifecycleRegistry()
    let renderer = DefaultRenderer()
    renderer.enableSelectiveEvaluation()
    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localLifecycleRegistry: lifecycleRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      LifecycleSelectiveTransparentAppearProbe(model: model),
      context: initialContext
    )
    let initialNode = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Count 0")
    )
    #expect(initialNode.lifecycleMetadata.appearHandlerIDs.count == 1)
    #expect(initialNode.lifecycleMetadata.disappearHandlerIDs.count == 1)

    invalidator.clear()
    model.count = 1
    let invalidated = collectedInvalidatedIdentities(from: invalidator)
    #expect(!invalidated.isEmpty)
    #expect(!invalidated.contains(testIdentity("Root")))

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidated,
      localLifecycleRegistry: lifecycleRegistry,
      applyEnvironmentValues: true
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      LifecycleSelectiveTransparentAppearProbe(model: model),
      context: updatedContext
    )
    let updatedNode = try #require(
      updatedArtifacts.resolvedTree.descendant(withText: "Count 1")
    )

    #expect(updatedNode.identity == initialNode.identity)
    #expect(
      updatedNode.lifecycleMetadata.appearHandlerIDs
        == initialNode.lifecycleMetadata.appearHandlerIDs)
    #expect(
      updatedNode.lifecycleMetadata.disappearHandlerIDs
        == initialNode.lifecycleMetadata.disappearHandlerIDs)
    #expect(updatedArtifacts.commitPlan.lifecycle.isEmpty)
  }

  @Test("transparent task owner still cancels and restarts when descriptor changes")
  func transparentTaskOwnerStillCancelsAndRestartsWhenDescriptorChanges() {
    let renderer = DefaultRenderer()

    _ = renderer.render(
      LifecycleSelectiveTaskReplacementProbe(label: "A", taskID: "first"),
      context: .init(identity: testIdentity("Root"))
    )
    let updated = renderer.render(
      LifecycleSelectiveTaskReplacementProbe(label: "A", taskID: "second"),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(
      updated.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "Group[0]"),
          operation: .taskCancel(
            .init(id: "Root/Group[0]#task[\"first\"]", priority: .userInitiated)
          )
        ),
        .init(
          identity: testIdentity("Root", "Group[0]"),
          operation: .taskStart(
            .init(id: "Root/Group[0]#task[\"second\"]", priority: .userInitiated)
          )
        ),
      ]
    )
  }

  @Test("transparent task owner still cancels when the task modifier is removed")
  func transparentTaskOwnerStillCancelsWhenTaskModifierIsRemoved() {
    let renderer = DefaultRenderer()

    _ = renderer.render(
      LifecycleSelectiveOptionalTaskProbe(label: "A", hasTask: true),
      context: .init(identity: testIdentity("Root"))
    )
    let updated = renderer.render(
      LifecycleSelectiveOptionalTaskProbe(label: "A", hasTask: false),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(
      updated.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "true", "Group[0]"),
          operation: .taskCancel(
            .init(id: "Root/true/Group[0]#task[\"optional\"]", priority: .userInitiated)
          )
        )
      ]
    )
  }
}

@Observable
private final class LifecycleSelectiveCounter {
  var count = 0
}

private struct LifecycleSelectiveTransparentTaskProbe: View {
  let model: LifecycleSelectiveCounter

  var body: some View {
    Group {
      LifecycleSelectiveCounterLabel(model: model)
    }
    .task(id: "stable") {}
  }
}

private struct LifecycleSelectiveTransparentAppearProbe: View {
  let model: LifecycleSelectiveCounter

  var body: some View {
    Group {
      LifecycleSelectiveCounterLabel(model: model)
    }
    .onAppear {}
    .onDisappear {}
  }
}

private struct LifecycleSelectiveCounterLabel: View {
  let model: LifecycleSelectiveCounter

  var body: some View {
    Text("Count \(model.count)")
  }
}

private struct LifecycleSelectiveTaskReplacementProbe: View {
  let label: String
  let taskID: String

  var body: some View {
    Group {
      Text(label)
    }
    .task(id: taskID) {}
  }
}

private struct LifecycleSelectiveOptionalTaskProbe: View {
  let label: String
  let hasTask: Bool

  var body: some View {
    if hasTask {
      Group {
        Text(label)
      }
      .task(id: "optional") {}
    } else {
      Group {
        Text(label)
      }
    }
  }
}

private final class LifecycleSelectiveRecordingInvalidator: Invalidating {
  var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }

  func clear() {
    requests.removeAll(keepingCapacity: true)
  }
}

private func collectedInvalidatedIdentities(
  from invalidator: LifecycleSelectiveRecordingInvalidator
) -> Set<Identity> {
  invalidator.requests.reduce(into: Set<Identity>()) { partial, request in
    partial.formUnion(request)
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }
}
