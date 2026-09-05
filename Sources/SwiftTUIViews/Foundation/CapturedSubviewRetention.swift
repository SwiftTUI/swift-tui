import SwiftTUICore

/// Declaring-owner identity for authored children that a style can place in a
/// different host or omit temporarily. This value retains no graph node.
package struct CapturedSubviewRetention: Sendable {
  package var owner: StateOwnerHandle
  package var identity: Identity

  @MainActor
  package func resolve(
    payloads: [ScopedContentPayload], in context: ResolveContext
  ) -> [ResolvedNode] {
    let ownerNode = context.viewGraph.flatMap { graph in
      owner.graphScope == graph.stateGraphScopeID
        ? graph.nodeForOwnerLifetimeID(owner.ownerLifetime) : nil
    }
    if let ownerNode, let archive = capturedSubviewArchive(in: ownerNode) {
      context.viewGraph?.restoreRetainedSubviewState(archive)
      storeCapturedSubviewArchive(nil, in: ownerNode)
    }

    // Logical ownership stays at the declaration. Structural placement,
    // inherited style values, focus, and runtime registries come from the host.
    let contentContext = context.replacingIdentity(with: identity)
    var children = CapturedSubviewSequenceView(payloads: payloads).resolveElements(
      in: contentContext)
    if !children.isEmpty {
      children[0].preferenceValues[ActiveCapturedSubviewOwnersPreferenceKey.self].insert(owner)
    }
    if let ownerNode, let graph = context.viewGraph {
      let locator = graph.dormantStateArchiveLocator(
        rootedAt: ResolvedNode(
          identity: identity, kind: .view("CapturedSubviewSequence"), children: children))
      withTransientDormantStateSlot {
        ownerNode.setStateSlotSilently(
          ordinal: StateSlotOrdinals.capturedSubviewLocator, value: locator)
      }
    }
    return children
  }
}

package enum CapturedSubviewOwnersPreferenceKey: PreferenceKey {
  package static let defaultValue: Set<StateOwnerHandle> = []
  package static func reduce(
    value: inout Set<StateOwnerHandle>, nextValue: () -> Set<StateOwnerHandle>
  ) { value.formUnion(nextValue()) }
}

package enum ActiveCapturedSubviewOwnersPreferenceKey: PreferenceKey {
  package static let defaultValue: Set<StateOwnerHandle> = []
  package static func reduce(
    value: inout Set<StateOwnerHandle>, nextValue: () -> Set<StateOwnerHandle>
  ) { value.formUnion(nextValue()) }
}

@MainActor
package struct CapturedSubviewArchiveCommitRefresh {
  package var owner: StateOwnerHandle
  package var archive: RetainedSubviewState
}

/// One-shot heads cannot rewind to an outgoing graph after resolution. Save
/// persistent-slot fallbacks before a structural replacement can evict nodes.
/// Abortable heads instead read the suspended live graph at tail completion.
@MainActor
package func captureCapturedSubviewHeadFallbacks(
  in graph: ViewGraph
) -> [CapturedSubviewArchiveCommitRefresh] {
  guard let root = graph.root else { return [] }
  let owners = root.committed.preferenceValues[CapturedSubviewOwnersPreferenceKey.self]
  return owners.compactMap { owner in
    guard let node = graph.nodeForOwnerLifetimeID(owner.ownerLifetime),
      let locator = node.stateSlotStorage(ordinal: StateSlotOrdinals.capturedSubviewLocator)?
        .value(as: DormantStateArchiveLocator.self), !locator.nodeIDs.isEmpty
    else { return nil }
    return .init(owner: owner, archive: graph.captureRetainedSubviewState(using: locator))
  }
}

/// Captures departing slots while the outgoing committed graph is available.
/// Active hosts have no archive: their live graph owns their state. An omitted
/// slot retains persistent state, with no focus, task, handler, or evaluator lifetime.
@MainActor
package func captureCapturedSubviewArchiveCommitRefreshes(
  in graph: ViewGraph, resolved: ResolvedNode,
  fallbacks: [CapturedSubviewArchiveCommitRefresh] = []
) -> [CapturedSubviewArchiveCommitRefresh] {
  let owners = resolved.preferenceValues[CapturedSubviewOwnersPreferenceKey.self]
  guard !owners.isEmpty else { return [] }
  let active = resolved.preferenceValues[ActiveCapturedSubviewOwnersPreferenceKey.self]
  return owners.subtracting(active).compactMap { owner in
    guard owner.graphScope == graph.stateGraphScopeID,
      let node = graph.nodeForOwnerLifetimeID(owner.ownerLifetime)
    else { return nil }
    guard
      let locator = node.stateSlotStorage(ordinal: StateSlotOrdinals.capturedSubviewLocator)?
        .value(as: DormantStateArchiveLocator.self)
    else { return nil }
    guard !locator.nodeIDs.isEmpty,
      locator.nodeIDs.allSatisfy({ graph.nodeForViewNodeID($0) != nil })
    else {
      return fallbacks.first { $0.owner == owner }
    }
    return .init(owner: owner, archive: graph.captureRetainedSubviewState(using: locator))
  }
}

/// Applied only after a completed candidate is accepted. Aborted/dropped
/// candidates never change the declaring owner's dormant state.
@MainActor
package func applyCapturedSubviewArchiveCommitRefreshes(
  _ refreshes: [CapturedSubviewArchiveCommitRefresh], in graph: ViewGraph
) {
  for refresh in refreshes {
    guard refresh.owner.graphScope == graph.stateGraphScopeID,
      let node = graph.nodeForOwnerLifetimeID(refresh.owner.ownerLifetime)
    else { continue }
    storeCapturedSubviewArchive(refresh.archive, in: node)
    withTransientDormantStateSlot {
      node.setStateSlotSilently(
        ordinal: StateSlotOrdinals.capturedSubviewLocator,
        value: DormantStateArchiveLocator(nodeIDs: []))
    }
  }
}

@MainActor
private func capturedSubviewArchive(in node: SwiftTUICore.ViewNode) -> RetainedSubviewState? {
  node.stateSlotStorage(ordinal: StateSlotOrdinals.capturedSubviewArchive)?
    .value(as: Optional<RetainedSubviewState>.self) ?? nil
}

@MainActor
private func storeCapturedSubviewArchive(
  _ archive: RetainedSubviewState?, in node: SwiftTUICore.ViewNode
) {
  withPersistentDormantStateSlot {
    node.setStateSlotSilently(ordinal: StateSlotOrdinals.capturedSubviewArchive, value: archive)
  }
}
