/// F29: the persistent copy-on-write node-image store behind
/// ``ViewGraph/makeCheckpoint()``.
///
/// Before this store, every abortable frame built TWO full per-node checkpoint
/// dictionaries from scratch (baseline at frame start, prepared after resolve)
/// — the Stage-2C probe measured that O(N) build as ~99.9% of checkpoint-create
/// cost. The store keeps one live image per node and refreshes only entries
/// whose owner mutated, so a capture costs one cheap generation-compare scan
/// plus O(touched) image rebuilds, and the handout is an O(1) COW copy of the
/// persistent dictionary.
///
/// **Soundness rests on monotonic generations** (F29 slice 1): every mutation
/// of a node's checkpoint-covered state bumps its generation through the
/// stored-property observers, and restores bump rather than rewind — so
/// "generation equal ⇒ state equal" holds and an entry whose captured
/// generation matches the node's live generation is byte-faithful. The
/// restore-a-just-made-checkpoint no-op oracle in ``ViewGraph/makeCheckpoint()``
/// verifies exactly this end to end.
///
/// The store is derived cache, not graph state: it is deliberately **outside**
/// the checkpointed field groups, it is never part of a checkpoint, and every
/// ``ViewGraph/restoreCheckpoint(_:)`` resets it wholesale from the restore
/// target.
@MainActor
package struct NodeCheckpointImageStore {
  /// One image per live node, current as of ``capturedGenerations``' entry.
  private var images: [ViewNodeID: ViewNode.Checkpoint] = [:]
  /// The node's checkpoint-mutation generation when its image was captured.
  /// Kept in lockstep with ``images`` (same key set). Deliberately separate
  /// from the image's own capture-metadata generation: after a restore the
  /// adopted images keep their original capture generations while the live
  /// nodes carry freshly bumped ones — re-pairing here (an O(N) integer map
  /// per adopt, measured ~35 µs at sheet scale) is what keeps post-restore
  /// captures from re-imaging every restore-rewritten node (an images-only
  /// variant was measured 2.5× worse on checkpoint create for identical
  /// whole-frame CPU).
  private var capturedGenerations: [ViewNodeID: UInt64] = [:]

  package init() {}

  /// Refreshes stale entries and returns the full image set for a checkpoint.
  ///
  /// One pass over the live nodes: an entry is stale iff its captured
  /// generation differs from the node's live generation (covers minted nodes —
  /// no entry means `nil != generation`). Departed nodes are pruned when the
  /// counts diverge; after the refresh loop `images.keys ⊇ live keys`, so
  /// equal counts imply equal key sets.
  ///
  /// The returned dictionary is the store's own storage — the checkpoint
  /// shares it copy-on-write, so an all-fresh capture allocates nothing and a
  /// capture with any refresh pays one storage duplication plus O(touched)
  /// image builds.
  package mutating func currentImages(
    of nodesByNodeID: [ViewNodeID: ViewNode]
  ) -> [ViewNodeID: ViewNode.Checkpoint] {
    for (viewNodeID, node) in nodesByNodeID
    where capturedGenerations[viewNodeID] != node.currentCheckpointMutationGeneration {
      images[viewNodeID] = node.makeCheckpoint()
      capturedGenerations[viewNodeID] = node.currentCheckpointMutationGeneration
    }
    if images.count != nodesByNodeID.count {
      let departedNodeIDs = images.keys.filter { nodesByNodeID[$0] == nil }
      for viewNodeID in departedNodeIDs {
        images.removeValue(forKey: viewNodeID)
        capturedGenerations.removeValue(forKey: viewNodeID)
      }
    }
    return images
  }

  /// Resets the store from a restore target: the graph has just been set to
  /// exactly `images`' state, so those images are the current ones by
  /// definition. Captured generations are re-read from the live nodes because
  /// restores bump generations rather than restore them — the adopted image of
  /// a rewritten node pairs with that node's fresh post-restore generation,
  /// and an untouched (gate-skipped) node keeps its unchanged one.
  package mutating func adopt(
    images: [ViewNodeID: ViewNode.Checkpoint],
    nodesByNodeID: [ViewNodeID: ViewNode]
  ) {
    self.images = images
    capturedGenerations = nodesByNodeID.mapValues { node in
      node.currentCheckpointMutationGeneration
    }
  }
}
