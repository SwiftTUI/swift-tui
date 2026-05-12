import Synchronization
import Testing

@testable import SwiftTUIRuntime
@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AnyViewResilienceTests {
  @Test("same erased static type preserves state across rerenders")
  func sameErasedTypePreservesStateAcrossRerenders() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      AnyView(
        AnyViewStateCounter(
          label: "Stable counter",
          buttonIdentity: testIdentity("StableCounterButton")
        )
      ),
      context: .init(
        identity: testIdentity("StableAnyView"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let actionIdentity = try #require(
      focusIdentity(containing: "StableCounterButton", in: initial)
    )

    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let updated = renderer.render(
      AnyView(
        AnyViewStateCounter(
          label: "Stable counter",
          buttonIdentity: testIdentity("StableCounterButton")
        )
      ),
      context: .init(
        identity: testIdentity("StableAnyView"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(updated.resolvedTree.descendant(withText: "Stable counter 1") != nil)
  }

  @Test("erased type swap destroys old state and starts new state")
  func erasedTypeSwapDestroysOldStateAndStartsNewState() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      AnyViewTypeSwapRoot(kind: .text),
      context: .init(
        identity: testIdentity("TypeSwap"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let actionIdentity = try #require(
      focusIdentity(containing: "TypeSwapButton", in: initial)
    )

    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let swapped = renderer.render(
      AnyViewTypeSwapRoot(kind: .stack),
      context: .init(
        identity: testIdentity("TypeSwap"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(swapped.resolvedTree.descendant(withText: "Stack counter 0") != nil)
    #expect(swapped.resolvedTree.descendant(withText: "Stack counter 1") == nil)
    #expect(swapped.resolvedTree.descendant(withText: "Text counter 1") == nil)
  }

  @Test("erased type swap cancels task and fires disappear")
  func erasedTypeSwapCancelsTaskAndFiresDisappear() throws {
    let renderer = DefaultRenderer()

    let initial = renderer.render(
      AnyViewLifecycleSwapRoot(kind: .text),
      context: .init(identity: testIdentity("LifecycleSwap"))
    )
    let removedIdentity = try #require(
      initial.resolvedTree.descendant(withText: "Lifecycle text")?.identity
    )

    let swapped = renderer.render(
      AnyViewLifecycleSwapRoot(kind: .stack),
      context: .init(identity: testIdentity("LifecycleSwap"))
    )
    let operations = lifecycleOperations(for: removedIdentity, in: swapped)

    #expect(operations.contains(where: isTaskCancel))
    #expect(operations.contains(where: isDisappear))
  }

  @Test("action inside scoped AnyView invalidates original owner")
  func actionInsideAnyViewInvalidatesOriginalOwner() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()
    let invalidator = AnyViewRecordingInvalidator()
    var context = ResolveContext(
      identity: testIdentity("ScopedOwner"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    context.invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)

    let initial = renderer.render(
      ScopedAnyViewActionOwner(),
      context: context
    )
    let actionIdentity = try #require(
      focusIdentity(containing: "ScopedAnyViewButton", in: initial)
    )

    #expect(
      actionRegistry.followUpInvalidationIdentity(for: actionIdentity)
        == testIdentity("ScopedOwner")
    )
    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let updated = renderer.render(
      ScopedAnyViewActionOwner(),
      context: .init(
        identity: testIdentity("ScopedOwner"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(updated.resolvedTree.descendant(withText: "Scoped count 1") != nil)
  }

  @Test("focusable descendant inside AnyView remains reachable")
  func focusableDescendantInsideAnyViewRemainsReachable() throws {
    let recorder = AnyViewEventRecorder()
    let renderer = DefaultRenderer()
    let firstRegistry = LocalActionRegistry()

    let initial = renderer.render(
      AnyView(AnyViewFocusableAction(recorder: recorder)),
      context: .init(
        identity: testIdentity("FocusableAnyView"),
        localActionRegistry: firstRegistry,
        applyEnvironmentValues: true
      )
    )

    let firstActionIdentity = try #require(
      focusIdentity(containing: "AnyViewFocusableButton", in: initial)
    )
    #expect(firstRegistry.dispatch(identity: firstActionIdentity))

    let secondRegistry = LocalActionRegistry()
    let updated = renderer.render(
      AnyView(AnyViewFocusableAction(recorder: recorder)),
      context: .init(
        identity: testIdentity("FocusableAnyView"),
        localActionRegistry: secondRegistry,
        applyEnvironmentValues: true
      )
    )

    let secondActionIdentity = try #require(
      focusIdentity(containing: "AnyViewFocusableButton", in: updated)
    )
    #expect(secondRegistry.dispatch(identity: secondActionIdentity))
    #expect(recorder.events == ["tap", "tap"])
  }

  @Test("nested AnyView uses each erased type boundary")
  func nestedAnyViewUsesEachErasedTypeBoundary() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      NestedAnyViewRoot(innerKind: .text),
      context: .init(
        identity: testIdentity("NestedAnyView"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )

    let actionIdentity = try #require(
      focusIdentity(containing: "NestedInnerButton", in: initial)
    )
    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let same = renderer.render(
      NestedAnyViewRoot(innerKind: .text),
      context: .init(
        identity: testIdentity("NestedAnyView"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )
    #expect(same.resolvedTree.descendant(withText: "Inner text 1") != nil)

    let initialOuterPayloads = initial.resolvedTree.descendantIdentities { node in
      node.kind == .view("AnyViewPayload")
        && node.identity.lastComponent?.contains("NestedAnyViewContainer") == true
    }
    let swapped = renderer.render(
      NestedAnyViewRoot(innerKind: .stack),
      context: .init(
        identity: testIdentity("NestedAnyView"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )
    let swappedOuterPayloads = swapped.resolvedTree.descendantIdentities { node in
      node.kind == .view("AnyViewPayload")
        && node.identity.lastComponent?.contains("NestedAnyViewContainer") == true
    }
    let swappedInnerTextPayloads = swapped.resolvedTree.descendantIdentities { node in
      node.kind == .view("AnyViewPayload")
        && node.identity.path.contains("AnyViewInnerTextCounter")
    }
    let swappedInnerStackPayloads = swapped.resolvedTree.descendantIdentities { node in
      node.kind == .view("AnyViewPayload")
        && node.identity.path.contains("AnyViewInnerStackCounter")
    }

    #expect(!initialOuterPayloads.isEmpty)
    #expect(swappedOuterPayloads == initialOuterPayloads)
    #expect(swapped.resolvedTree.descendant(withText: "Inner stack 0") != nil)
    #expect(swappedInnerTextPayloads.isEmpty)
    #expect(!swappedInnerStackPayloads.isEmpty)
  }

  @Test("explicit ID inside AnyView does not defeat type-swap teardown")
  func explicitIDInsideAnyViewDoesNotDefeatTypeSwapTeardown() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      ExplicitIDAnyViewRoot(kind: .text),
      context: .init(
        identity: testIdentity("ExplicitIDAnyView"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let actionIdentity = try #require(
      focusIdentity(containing: "ExplicitIDCounterButton", in: initial)
    )
    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let swapped = renderer.render(
      ExplicitIDAnyViewRoot(kind: .stack),
      context: .init(
        identity: testIdentity("ExplicitIDAnyView"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(swapped.resolvedTree.descendant(withText: "Explicit stack 0") != nil)
    #expect(swapped.resolvedTree.descendant(withText: "Explicit stack 1") == nil)
  }

  @Test("ForEach inside AnyView keeps element identities")
  func forEachInsideAnyViewKeepsElementIdentities() throws {
    let renderer = DefaultRenderer()
    let actionRegistry = LocalActionRegistry()

    let initial = renderer.render(
      AnyViewForEachRoot(items: [1, 2, 3]),
      context: .init(
        identity: testIdentity("ForEachAnyView"),
        localActionRegistry: actionRegistry,
        applyEnvironmentValues: true
      )
    )
    let actionIdentity = try #require(
      focusIdentity(containing: "AnyViewRow2Button", in: initial)
    )

    #expect(actionRegistry.dispatch(identity: actionIdentity))

    let reordered = renderer.render(
      AnyViewForEachRoot(items: [3, 2, 1]),
      context: .init(
        identity: testIdentity("ForEachAnyView"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(reordered.resolvedTree.descendant(withText: "Row 1 count 0") != nil)
    #expect(reordered.resolvedTree.descendant(withText: "Row 2 count 1") != nil)
    #expect(reordered.resolvedTree.descendant(withText: "Row 3 count 0") != nil)
  }
}

private enum AnyViewCounterKind {
  case text
  case stack
}

private struct AnyViewStateCounter: View {
  let label: String
  let buttonIdentity: Identity

  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(label) \(count)")
      Button(
        "Increment \(label)",
        action: {
          count += 1
        }
      )
      .id(buttonIdentity)
    }
  }
}

private struct AnyViewTypeSwapRoot: View {
  let kind: AnyViewCounterKind

  var body: AnyView {
    switch kind {
    case .text:
      return AnyView(
        AnyViewTextCounter(
          label: "Text counter",
          buttonIdentity: testIdentity("TypeSwapButton")
        )
      )
    case .stack:
      return AnyView(
        AnyViewStackCounter(
          label: "Stack counter",
          buttonIdentity: testIdentity("TypeSwapButton")
        )
      )
    }
  }
}

private struct AnyViewTextCounter: View {
  let label: String
  let buttonIdentity: Identity

  @State(line: 1_001, column: 1) private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(label) \(count)")
      Button(
        "Increment \(label)",
        action: {
          count += 1
        }
      )
      .id(buttonIdentity)
    }
  }
}

private struct AnyViewStackCounter: View {
  let label: String
  let buttonIdentity: Identity

  @State(line: 1_001, column: 1) private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Group {
        Text("\(label) \(count)")
      }
      Button(
        "Increment \(label)",
        action: {
          count += 1
        }
      )
      .id(buttonIdentity)
    }
  }
}

private struct AnyViewLifecycleSwapRoot: View {
  let kind: AnyViewCounterKind

  var body: AnyView {
    switch kind {
    case .text:
      return AnyView(AnyViewLifecycleTextPayload())
    case .stack:
      return AnyView(AnyViewLifecycleStackPayload())
    }
  }
}

private struct AnyViewLifecycleTextPayload: View {
  var body: some View {
    Text("Lifecycle text")
      .onAppear {}
      .onDisappear {}
      .task(id: "lifecycle-load") {}
  }
}

private struct AnyViewLifecycleStackPayload: View {
  var body: some View {
    Text("Lifecycle stack")
      .onAppear {}
      .onDisappear {}
      .task(id: "lifecycle-load") {}
  }
}

private struct ScopedAnyViewActionOwner: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Scoped count \(count)")
      ScopedAnyViewHost(
        content: scopedAnyView {
          Button(
            "Scoped action",
            action: {
              count += 1
            }
          )
          .id(testIdentity("ScopedAnyViewButton"))
        }
      )
    }
  }
}

private struct ScopedAnyViewHost: PrimitiveView, ResolvableView {
  let content: AnyView

  var body: Never {
    fatalError("ScopedAnyViewHost resolves stored content directly.")
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      content.resolve(
        in: context.child(component: .named("ScopedAnyViewContent"))
      )
    ]
  }
}

private struct AnyViewFocusableAction: View {
  let recorder: AnyViewEventRecorder

  var body: some View {
    Button(
      "Focusable action",
      action: {
        recorder.record("tap")
      }
    )
    .id(testIdentity("AnyViewFocusableButton"))
  }
}

private struct NestedAnyViewRoot: View {
  let innerKind: AnyViewCounterKind

  var body: AnyView {
    AnyView(NestedAnyViewContainer(innerKind: innerKind))
  }
}

private struct NestedAnyViewContainer: View {
  let innerKind: AnyViewCounterKind

  var body: AnyView {
    switch innerKind {
    case .text:
      return AnyView(
        AnyViewInnerTextCounter(
          label: "Inner text",
          buttonIdentity: testIdentity("NestedInnerButton")
        )
      )
    case .stack:
      return AnyView(
        AnyViewInnerStackCounter(
          label: "Inner stack",
          buttonIdentity: testIdentity("NestedInnerButton")
        )
      )
    }
  }
}

private struct AnyViewInnerTextCounter: View {
  let label: String
  let buttonIdentity: Identity

  @State(line: 2_001, column: 1) private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(label) \(count)")
      Button(
        "Increment \(label)",
        action: {
          count += 1
        }
      )
      .id(buttonIdentity)
    }
  }
}

private struct AnyViewInnerStackCounter: View {
  let label: String
  let buttonIdentity: Identity

  @State(line: 2_001, column: 1) private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Group {
        Text("\(label) \(count)")
      }
      Button(
        "Increment \(label)",
        action: {
          count += 1
        }
      )
      .id(buttonIdentity)
    }
  }
}

private struct ExplicitIDAnyViewRoot: View {
  let kind: AnyViewCounterKind

  var body: AnyView {
    switch kind {
    case .text:
      return AnyView(ExplicitIDTextCounter())
    case .stack:
      return AnyView(ExplicitIDStackCounter())
    }
  }
}

private struct ExplicitIDTextCounter: View {
  var body: some View {
    AnyViewTextCounter(
      label: "Explicit text",
      buttonIdentity: testIdentity("ExplicitIDCounterButton")
    )
    .id(testIdentity("StableInnerExplicitID"))
  }
}

private struct ExplicitIDStackCounter: View {
  var body: some View {
    AnyViewStackCounter(
      label: "Explicit stack",
      buttonIdentity: testIdentity("ExplicitIDCounterButton")
    )
    .id(testIdentity("StableInnerExplicitID"))
  }
}

private struct AnyViewForEachRoot: View {
  let items: [Int]

  var body: AnyView {
    AnyView(
      ForEach(items, id: \.self) { value in
        AnyViewRowCounter(value: value)
      }
    )
  }
}

private struct AnyViewRowCounter: View {
  let value: Int

  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Row \(value) count \(count)")
      Button(
        "Increment row \(value)",
        action: {
          count += 1
        }
      )
      .id(testIdentity("AnyViewRow\(value)Button"))
    }
  }
}

private final class AnyViewEventRecorder: Sendable {
  private let storage = Mutex<[String]>([])

  var events: [String] {
    storage.withLock { $0 }
  }

  func record(_ event: String) {
    storage.withLock { events in
      events.append(event)
    }
  }
}

private final class AnyViewRecordingInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}

private func lifecycleOperations(
  for identity: Identity,
  in artifacts: FrameArtifacts
) -> [LifecycleCommitOperation] {
  artifacts.commitPlan.lifecycle
    .filter { $0.identity == identity }
    .map(\.operation)
}

private func focusIdentity(
  containing marker: String,
  in artifacts: FrameArtifacts
) -> Identity? {
  artifacts.semanticSnapshot.focusRegions.first {
    $0.identity.path.contains(marker)
  }?.identity
}

private func isDisappear(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .disappear = operation {
    return true
  }
  return false
}

private func isTaskCancel(
  _ operation: LifecycleCommitOperation
) -> Bool {
  if case .taskCancel = operation {
    return true
  }
  return false
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if case .text(let value) = drawPayload, value == text {
      return self
    }

    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }

    return nil
  }

  fileprivate func descendantIdentities(
    matching predicate: (ResolvedNode) -> Bool
  ) -> [Identity] {
    var matches: [Identity] = predicate(self) ? [identity] : []
    for child in children {
      matches.append(contentsOf: child.descendantIdentities(matching: predicate))
    }
    return matches
  }

  fileprivate func firstDescendant(
    withKind kind: NodeKind
  ) -> ResolvedNode? {
    if self.kind == kind {
      return self
    }

    for child in children {
      if let match = child.firstDescendant(withKind: kind) {
        return match
      }
    }

    return nil
  }
}
