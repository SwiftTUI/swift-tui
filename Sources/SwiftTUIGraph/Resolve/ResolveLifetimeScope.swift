// Automatic lifetime classification for resolved runtime nodes. The task-local
// stack follows nested `resolveView` calls without adding checkpointed mutable
// state to `ViewGraph`: every frame closes before its resolve call returns.

@MainActor
private final class ResolveLifetimeScopeFrame {
  weak var graph: ViewGraph?
  let hostNodeID: ViewNodeID
  var observedNodeIDs: Set<ViewNodeID> = []
  var manualHostedNodeIDs: Set<ViewNodeID> = []

  init(graph: ViewGraph, hostNodeID: ViewNodeID) {
    self.graph = graph
    self.hostNodeID = hostNodeID
  }
}

@MainActor
private enum ResolveLifetimeScopeContext {
  @TaskLocal static var current: ResolveLifetimeScopeFrame?
}

extension ViewGraph {
  /// Runs one fresh view evaluation inside a LIFO lifetime scope. Child
  /// `resolveView` results report into this frame; after the host finishes its
  /// apply, the frame distinguishes committed/durably anchored results from
  /// detached results whose lifetime must follow this host.
  package func withResolveLifetimeScope<Result>(
    hostedBy host: ViewNode,
    _ body: () -> Result
  ) -> Result {
    let frame = ResolveLifetimeScopeFrame(
      graph: self,
      hostNodeID: host.viewNodeID
    )
    return ResolveLifetimeScopeContext.$current.withValue(frame) {
      let result = body()
      closeResolveLifetimeScope(frame)
      return result
    }
  }

  /// Reinstalls the captured live host for delayed indexed-child realization,
  /// which runs outside the original `resolveView` call stack.
  package func withCapturedResolveLifetimeScope<Result>(
    hostedBy host: ViewNode?,
    _ body: () -> Result
  ) -> Result {
    guard let host,
      nodeIfExists(for: host.viewNodeID) === host
    else {
      return body()
    }
    return ViewNodeContext.withCurrentValue(host) {
      withResolveLifetimeScope(hostedBy: host, body)
    }
  }

  /// Reports a fresh/adopted runtime node to the current parent scope before
  /// its own scope opens.
  package func reportResolvedLifetimeNode(_ node: ViewNode) {
    guard let frame = ResolveLifetimeScopeContext.current,
      frame.graph === self,
      frame.hostNodeID != node.viewNodeID
    else {
      return
    }
    frame.observedNodeIDs.insert(node.viewNodeID)
  }

  /// Reports the root returned by a reused resolve. Fresh resolves already
  /// report their runtime node before opening their nested scope; this also
  /// covers a collapsed result whose returned stamp differs from that node.
  package func reportResolvedLifetimeResult(_ resolved: ResolvedNode) {
    guard let frame = ResolveLifetimeScopeContext.current,
      frame.graph === self,
      let nodeID = resolved.viewNodeID ?? nodeIfExists(for: resolved.identity)?.viewNodeID,
      frame.hostNodeID != nodeID
    else {
      return
    }
    frame.observedNodeIDs.insert(nodeID)
  }

  func recordManualResolveLifetimeAnchor(
    rootNodeID: ViewNodeID,
    hostedByNodeID hostNodeID: ViewNodeID
  ) {
    guard let frame = ResolveLifetimeScopeContext.current,
      frame.graph === self,
      frame.hostNodeID == hostNodeID
    else {
      return
    }
    frame.manualHostedNodeIDs.insert(rootNodeID)
  }

  private func closeResolveLifetimeScope(_ frame: ResolveLifetimeScopeFrame) {
    guard frame.graph === self,
      nodeIfExists(for: frame.hostNodeID) != nil
    else {
      return
    }

    var automaticallyHosted: Set<ViewNodeID> = []
    var classifiedNodeIDs: Set<ViewNodeID> = []
    for nodeID in frame.observedNodeIDs.sorted() {
      guard nodeID != frame.hostNodeID else {
        continue
      }
      // A sibling can deliberately replace/remove a candidate before the
      // enclosing scope closes. There is no stored lifetime left to classify.
      guard nodeIfExists(for: nodeID) != nil else {
        continue
      }
      let anchors = lifetimeAnchors.anchors(for: nodeID)
      if anchors.contains(.parent(frame.hostNodeID))
        || anchors.contains(.committedValue(frame.hostNodeID))
      {
        classifiedNodeIDs.insert(nodeID)
        continue
      }

      let hasOtherDurableAnchor = anchors.contains { anchor in
        switch anchor {
        case .evaluationHost:
          return false
        case .hostedDetached(let source):
          return source != frame.hostNodeID && nodeIfExists(for: source) != nil
        case .parent(let source),
          .committedValue(let source),
          .navigationSurface(let source):
          return nodeIfExists(for: source) != nil
        case .entityHome:
          return true
        }
      }
      if hasOtherDurableAnchor {
        classifiedNodeIDs.insert(nodeID)
        continue
      }

      // A completed `resolveView` result reported to this parent scope is a
      // durable detached result when the host's finished apply did not commit
      // it and no other durable owner claimed it. An intentional scratch mint
      // is explicit `.resolveScopeScratch` debt rather than a reported result.
      automaticallyHosted.insert(nodeID)
      classifiedNodeIDs.insert(nodeID)
      recordDetachedHostedNode(nodeID, hostedByNodeID: frame.hostNodeID)
      SoundnessProbeConfiguration.recordAutomaticLifetimeAnchor()
    }

    let unexplainedManual = frame.manualHostedNodeIDs.subtracting(classifiedNodeIDs)
    if !unexplainedManual.isEmpty {
      let detail =
        "manual hosted nodes were not classified host=\(frame.hostNodeID) missing=\(unexplainedManual)"
      SoundnessProbeConfiguration.recordResolveLifetimeScopeManualMismatch(
        detail
      )
      assertionFailure(detail)
    }
  }
}
