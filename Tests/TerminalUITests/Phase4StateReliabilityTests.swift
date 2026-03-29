import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite(.serialized)
struct Phase4StateReliabilityTests {
  @Test(
    "@State button actions stay bound to their original identity when the same view instance is rebound inside one runtime store"
  )
  func stateButtonActionsStayBoundToOriginalIdentityInOneStore() throws {
    let view = Phase4StatefulCounterView()
    let store = DynamicStateStore(invalidationIdentities: [testIdentity("Root")])
    let firstActionRegistry = LocalActionRegistry()
    let secondActionRegistry = LocalActionRegistry()

    var firstContext = ResolveContext(
      identity: testIdentity("Root", "CounterA"),
      localActionRegistry: firstActionRegistry,
      applyEnvironmentValues: true
    )
    firstContext.dynamicStateStore = store
    let firstArtifacts = DefaultRenderer().render(
      view,
      context: firstContext
    )
    let firstActionIdentity = try #require(
      firstArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    var secondContext = ResolveContext(
      identity: testIdentity("Root", "CounterB"),
      localActionRegistry: secondActionRegistry,
      applyEnvironmentValues: true
    )
    secondContext.dynamicStateStore = store
    let secondArtifacts = DefaultRenderer().render(
      view,
      context: secondContext
    )
    let secondActionIdentity = try #require(
      secondArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    #expect(firstActionIdentity != secondActionIdentity)
    #expect(firstActionRegistry.dispatch(identity: firstActionIdentity))

    let updatedFirstArtifacts = DefaultRenderer().render(
      view,
      context: firstContext
    )
    let updatedSecondArtifacts = DefaultRenderer().render(
      view,
      context: secondContext
    )

    #expect(updatedFirstArtifacts.rasterSurface.lines.contains("Count 1"))
    #expect(updatedSecondArtifacts.rasterSurface.lines.contains("Count 0"))
  }

  @Test("@State button actions invalidate only the owning subtree identity through wrapper views")
  func stateButtonActionsInvalidateOnlyOwningSubtree() throws {
    let invalidator = Phase4StateRecordingInvalidator()
    let store = DynamicStateStore(invalidationIdentities: [testIdentity("Root")])
    store.invalidator = invalidator
    let actionRegistry = LocalActionRegistry()
    let renderer = DefaultRenderer()

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localActionRegistry: actionRegistry,
      applyEnvironmentValues: true
    )
    initialContext.dynamicStateStore = store

    let initialArtifacts = renderer.render(
      Phase4NestedStateRoot(),
      context: initialContext
    )
    let actionIdentity = try #require(
      initialArtifacts.semanticSnapshot.focusRegions.first?.identity
    )

    #expect(actionRegistry.dispatch(identity: actionIdentity))
    #expect(invalidator.requests == [[testIdentity("CounterOwner")]])

    var updatedContext = initialContext
    updatedContext.invalidatedIdentities = invalidator.requests[0]
    let updatedArtifacts = renderer.render(
      Phase4NestedStateRoot(),
      context: updatedContext
    )

    #expect(updatedArtifacts.rasterSurface.lines.contains(where: { $0.contains("Count 1") }))
    #expect(updatedArtifacts.rasterSurface.lines.contains("Static sibling"))
    #expect(updatedArtifacts.diagnostics.resolvedNodesReused >= 1)
    #expect(updatedArtifacts.diagnostics.measuredNodesReused >= 1)
    #expect(updatedArtifacts.diagnostics.placedNodesReused >= 1)
  }
}

private struct Phase4StatefulCounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Count \(count)")
      Button(
        "Increment",
        action: {
          count += 1
        }
      )
    }
  }
}

private struct Phase4NestedStateRoot: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Phase4StatefulCounterView()
        .id(testIdentity("CounterOwner"))
        .padding(.init(all: 1))
      Text("Static sibling")
    }
  }
}

private final class Phase4StateRecordingInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}
