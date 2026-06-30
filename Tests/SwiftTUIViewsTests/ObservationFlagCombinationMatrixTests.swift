import Observation
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Minimal observable model mirroring the production `Observation` bridge: a
/// single key-path-precise property backed by an `ObservationRegistrar`. File
/// scoped (like the sibling dependency-model probes) so `Observable` conformance
/// and key-path inference resolve without enclosing-type isolation interference.
private final class ObservationMatrixModel: Observable, Sendable {
  private let registrar = ObservationRegistrar()
  private let hotStorage = Mutex(0)

  var hot: Int {
    get {
      registrar.access(self, keyPath: \.hot)
      return hotStorage.withLock { $0 }
    }
    set {
      registrar.withMutation(of: self, keyPath: \.hot) {
        hotStorage.withLock { $0 = newValue }
      }
    }
  }
}

/// Reads the observable via `@Bindable` — the seam that records an object token.
private struct ObservableReaderProbe: View {
  @Bindable var model: ObservationMatrixModel

  init(model: ObservationMatrixModel) {
    _model = Bindable(model)
  }

  var body: some View {
    Text("\($model.hot.wrappedValue)")
  }
}

/// Owns `@State` and only PROJECTS it to a distinct descendant reader, so reader
/// attribution has somewhere to move the edge to.
private struct StateReaderProbe: View {
  @State private var flag = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("static-sibling")
      StateBindingReader(flag: $flag)
    }
  }
}

private struct StateBindingReader: View {
  @Binding var flag: Bool

  var body: some View {
    Text(flag ? "on" : "off")
  }
}

/// Locks the **safety invariant of the observation/invalidation model.**
///
/// Observable change invalidation dirties only the precise firing node (the
/// `withObservationTracking` `onChange` already fired for exactly the node that
/// read the mutated property), and `@State` reads are attributed to the genuine
/// reader rather than the slot owner. Both are documented as *over-invalidate,
/// never under*: a genuine reader's dependency edge must always be recorded so a
/// change can never make a reader silently go deaf. This suite resolves a fixed
/// reader and asserts that edge is always present.
///
/// (Previously this matrix exercised 16 on/off combinations of four narrowing
/// gates; those gates are now unconditional, so the single shipping
/// configuration is the only thing left to lock.)
@MainActor
struct ObservationFlagCombinationMatrixTests {
  private func resolvedRootDependencies<V: View>(_ view: V) -> DependencySet? {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)
    return graph.dependencies(for: testIdentity("Root"))
  }

  private func stateDependentIdentities<V: View>(_ view: V) -> Set<String> {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(view, in: context)

    let snapshot = graph.debugTotalStateSnapshot()
    var identities: Set<String> = []
    for (_, dependents) in snapshot.stateSlotDependents {
      for nodeID in dependents {
        if let identity = snapshot.identityByNodeID[nodeID] {
          identities.insert(identity.description)
        }
      }
    }
    return identities
  }

  @Test("observable object-token edge is recorded for a genuine reader")
  func observableTokenEdgeRecorded() throws {
    let model = ObservationMatrixModel()
    let dependencies = resolvedRootDependencies(ObservableReaderProbe(model: model))
    let recorded = try #require(
      dependencies,
      "no dependencies recorded for the observable reader"
    )
    #expect(
      recorded.observableReads.contains(ObjectIdentifier(model)),
      "the observable reader's object-token edge was dropped"
    )
  }

  @Test("a genuine @State reader is never orphaned")
  func stateReaderEdgeRecorded() {
    let dependents = stateDependentIdentities(StateReaderProbe())
    // Reader attribution moves the edge from the projecting owner to the genuine
    // reader. A dependent must exist — an empty set would mean a `@State` write
    // reaches no node and the reader silently goes deaf.
    #expect(
      !dependents.isEmpty,
      "the @State reader's dependency edge was dropped"
    )
  }
}
