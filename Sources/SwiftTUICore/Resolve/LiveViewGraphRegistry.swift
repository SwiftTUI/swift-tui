/// Maps a ``StateGraphScopeID`` back to its live ``ViewGraph``.
///
/// `@State` reads and writes that happen *outside* a resolve pass — an
/// autonomous `.task`, a gesture callback, any imperative action — carry only a
/// sendable identity snapshot (`ownerNodeID` + `stateGraphScope`); they
/// deliberately drop the `ViewNode` reference so they cannot pin a retired
/// graph. To reach the graph-backed state slot they must recover the live owner
/// node, which means recovering the live graph for the captured scope. During a
/// resolve pass `ViewNodeContext.current?.ownerGraph` supplies it; this registry
/// supplies it everywhere else.
///
/// Entries are **weak**: a graph that has been retired (or a transient
/// `DefaultRenderer` snapshot graph that never owned an invalidator) resolves to
/// `nil`, and the imperative read falls back to the per-box seed exactly as it
/// did before this registry existed. Lookups therefore stay graph-scoped to the
/// session that registered the work — they can never bind imperative state to a
/// *different* live graph, so mutations cannot leak across sessions. Dead
/// entries are pruned opportunistically on registration; no `deinit` cleanup is
/// required because the weak reference already drops the graph.
@MainActor
package enum LiveViewGraphRegistry {
  private final class WeakViewGraphRef {
    weak var graph: ViewGraph?
    init(_ graph: ViewGraph) {
      self.graph = graph
    }
  }

  private static var graphsByScope: [StateGraphScopeID: WeakViewGraphRef] = [:]

  /// Records `graph` under its scope identity, sweeping any entries whose graph
  /// has since been deallocated. Idempotent — a graph re-registers under the
  /// same key.
  package static func register(_ graph: ViewGraph) {
    graphsByScope = graphsByScope.filter { $0.value.graph != nil }
    graphsByScope[StateGraphScopeID(graph)] = WeakViewGraphRef(graph)
  }

  /// The live graph for `scope`, or `nil` if it has been retired (or was never
  /// registered).
  package static func graph(for scope: StateGraphScopeID) -> ViewGraph? {
    graphsByScope[scope]?.graph
  }
}
