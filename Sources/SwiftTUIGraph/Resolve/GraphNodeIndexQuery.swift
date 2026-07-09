/// Read-only lookups over ``ViewGraph``'s identity / view-node-ID / structural
/// indices, lifted off the god class into one cohesive, testable place.
///
/// Like ``GraphCheckpointStore``, this is a **stateless operator** (a caseless
/// `enum` of static funcs taking the ``ViewGraph/GraphIndex`` group as a
/// parameter): the index stays on `ViewGraph` — it sits on the per-frame hot
/// path and the checkpoint-totality guard pins `ViewGraph`'s stored properties
/// to the nine field groups plus `root` — so the operator adds zero stored
/// state. Only the **pure reads** move here; the index *mutators* (node
/// creation, `reindexIdentity`/`reindexStructuralPath`, `applyResolvedNode`)
/// stay on `ViewGraph`, where they own the writes.
@MainActor
package enum GraphNodeIndexQuery {
  /// The live node for `identity`, or `nil` if it is not in the graph.
  package static func node(
    for identity: Identity,
    in index: ViewGraph.GraphIndex
  ) -> ViewNode? {
    guard let viewNodeID = index.nodeIDByIdentity[identity] else {
      return nil
    }
    return index.nodesByNodeID[viewNodeID]
  }

  /// The live node for `viewNodeID`, or `nil` if it is not in the graph.
  package static func node(
    for viewNodeID: ViewNodeID,
    in index: ViewGraph.GraphIndex
  ) -> ViewNode? {
    index.nodesByNodeID[viewNodeID]
  }

  /// The view-node ID currently mapped to `identity`, if any.
  package static func viewNodeID(
    for identity: Identity,
    in index: ViewGraph.GraphIndex
  ) -> ViewNodeID? {
    index.nodeIDByIdentity[identity]
  }

  /// Every view-node ID that could correspond to `resolved` — the structural
  /// path's set, plus the resolved node's own stamped ID when present.
  package static func nodeIDs(
    forResolvedNode resolved: ResolvedNode,
    in index: ViewGraph.GraphIndex
  ) -> Set<ViewNodeID> {
    var viewNodeIDs = index.nodeIDsByStructuralPath[resolved.structuralPath] ?? []
    if let viewNodeID = resolved.viewNodeID {
      viewNodeIDs.insert(viewNodeID)
    }
    return viewNodeIDs
  }

  /// The identities currently mapped from `viewNodeIDs`.
  package static func identities(
    for viewNodeIDs: Set<ViewNodeID>,
    in index: ViewGraph.GraphIndex
  ) -> Set<Identity> {
    Set(viewNodeIDs.compactMap { index.identityByNodeID[$0] })
  }

  /// The view-node IDs currently mapped from `identities`.
  package static func nodeIDs(
    for identities: Set<Identity>,
    in index: ViewGraph.GraphIndex
  ) -> Set<ViewNodeID> {
    Set(identities.compactMap { index.nodeIDByIdentity[$0] })
  }
}
