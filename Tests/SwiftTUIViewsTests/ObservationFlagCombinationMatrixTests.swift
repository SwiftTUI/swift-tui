import Observation
import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

private struct FlagCombination: Sendable, CustomStringConvertible {
  var precise: Bool
  var keyPath: Bool
  var readerAttribution: Bool
  var memoReuse: Bool

  var description: String {
    "precise=\(precise) keyPath=\(keyPath) reader=\(readerAttribution) memo=\(memoReuse)"
  }
}

/// All 16 on/off configurations of the four observation/invalidation gates.
/// File-scoped so the `@Test(arguments:)` macro can read it from the nonisolated
/// argument-collection context (a `@MainActor` suite static cannot be).
private let allFlagCombinations: [FlagCombination] = {
  var combinations: [FlagCombination] = []
  for precise in [false, true] {
    for keyPath in [false, true] {
      for readerAttribution in [false, true] {
        for memoReuse in [false, true] {
          combinations.append(
            FlagCombination(
              precise: precise,
              keyPath: keyPath,
              readerAttribution: readerAttribution,
              memoReuse: memoReuse
            )
          )
        }
      }
    }
  }
  return combinations
}()

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

/// Reads the observable via `@Bindable` — the seam that records an object token
/// (and, in key-path mode, a `(object, keyPath)` pair).
private struct ObservableReaderProbe: View {
  @Bindable var model: ObservationMatrixModel

  init(model: ObservationMatrixModel) {
    _model = Bindable(model)
  }

  var body: some View {
    Text("\($model.hot.wrappedValue)")
  }
}

/// Owns `@State` and only PROJECTS it to a distinct descendant reader, so the
/// reader-attribution narrowing has somewhere to move the edge to.
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

/// Locks the **safety invariant of the observation/invalidation flag fork.**
///
/// Four narrowing gates govern how a read records and re-invalidates its
/// dependency:
/// - ``PreciseObservationFiringConfiguration`` (drop the co-reader union),
/// - ``ObservableKeyPathInvalidationConfiguration`` (narrow the union to the
///   same `(object, keyPath)`),
/// - ``ReaderAttributionConfiguration`` (attribute `@State` reads to the genuine
///   reader rather than the slot owner),
/// - ``MemoReuseConfiguration`` (skip an `Equatable`-equal body).
///
/// They combine into 16 on/off configurations, and only the default-on corner
/// plus a handful of singletons were ever exercised — the survey flagged the
/// untested off-combinations as a latent under-invalidation landmine. Each gate
/// is documented as *over-invalidate, never under*: it may widen the dirty set
/// but must never DROP the dependency edge a genuine reader relies on. This
/// suite resolves a fixed reader under every one of the 16 combinations and
/// asserts that edge is always recorded — so no off-combination can silently go
/// deaf.
///
/// Serialized because it flips process-level configuration flags.
@MainActor
@Suite(.serialized)
struct ObservationFlagCombinationMatrixTests {
  private func withFlags<R>(
    _ combination: FlagCombination,
    _ body: () throws -> R
  ) rethrows -> R {
    let previousPrecise = PreciseObservationFiringConfiguration.isEnabled
    let previousKeyPath = ObservableKeyPathInvalidationConfiguration.isEnabled
    let previousReader = ReaderAttributionConfiguration.isEnabled
    let previousMemo = MemoReuseConfiguration.isEnabled
    PreciseObservationFiringConfiguration.isEnabled = combination.precise
    ObservableKeyPathInvalidationConfiguration.isEnabled = combination.keyPath
    ReaderAttributionConfiguration.isEnabled = combination.readerAttribution
    MemoReuseConfiguration.isEnabled = combination.memoReuse
    defer {
      PreciseObservationFiringConfiguration.isEnabled = previousPrecise
      ObservableKeyPathInvalidationConfiguration.isEnabled = previousKeyPath
      ReaderAttributionConfiguration.isEnabled = previousReader
      MemoReuseConfiguration.isEnabled = previousMemo
    }
    return try body()
  }

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

  @Test(
    "observable object-token edge survives every flag combination",
    arguments: allFlagCombinations
  )
  private func observableTokenEdgeSurvivesEveryCombination(
    _ combination: FlagCombination
  ) throws {
    let model = ObservationMatrixModel()
    let dependencies = withFlags(combination) {
      resolvedRootDependencies(ObservableReaderProbe(model: model))
    }
    let recorded = try #require(
      dependencies,
      "no dependencies recorded for the observable reader under \(combination)"
    )
    // The object token is recorded ALONGSIDE any key-path index, never replaced
    // (the key-path narrowing is additive), and precise firing only changes the
    // firing fan-out, not what the reader records. So a genuine reader's object
    // edge must be present in every one of the 16 configurations.
    #expect(
      recorded.observableReads.contains(ObjectIdentifier(model)),
      "the observable reader's object-token edge was dropped under \(combination)"
    )
  }

  @Test(
    "genuine @State reader is never orphaned across flag combinations",
    arguments: allFlagCombinations
  )
  private func stateReaderEdgeSurvivesEveryCombination(_ combination: FlagCombination) {
    let dependents = withFlags(combination) {
      stateDependentIdentities(StateReaderProbe())
    }
    // Reader attribution MOVES the edge from the projecting owner to the genuine
    // reader; legacy mode keeps it on the owner. Either way a dependent must
    // exist — an empty set would mean a `@State` write reaches no node and the
    // reader silently goes deaf.
    #expect(
      !dependents.isEmpty,
      "the @State reader's dependency edge was dropped under \(combination)"
    )
  }
}
