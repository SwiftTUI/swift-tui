@_spi(Testing) import SwiftTUIPrimitives

package enum RetainedPhaseExtractionProof: Equatable, Sendable {
  case none
  case wholeTreeIdentical
  case subtreesIdentical(Set<Identity>)

  package func canReuseSubtree(rootedAt identity: Identity) -> Bool {
    switch self {
    case .none:
      return false
    case .wholeTreeIdentical:
      return true
    case .subtreesIdentical(let identities):
      return identities.contains(identity)
    }
  }
}

/// Per-node phase-extraction signature vocabulary plus the paired
/// subtree-equivalence walk the frame tail uses for phase reuse.
///
/// `NodeSignature` is the total mirror of the `PlacedNode` fields the
/// retained draw/semantics products depend on (locked against `PlacedNode`'s
/// stored fields by `PlacedNodeMirrorTotalityTests`). `subtreesIdentical`
/// compares two placed subtrees one node pair at a time and short-circuits on
/// the first difference — it replaced the historical whole-subtree signature
/// arrays, which were rebuilt per reuse candidate at every descent level
/// (O(n·depth) node copies per frame on partial-reuse frames).
package enum RetainedPhaseExtractionSignature {
  private struct NodeSignature: Equatable, Sendable {
    var identity: Identity
    var kind: NodeKind
    var environmentSnapshot: EnvironmentSnapshot
    var bounds: CellRect
    var contentBounds: CellRect
    var clipBounds: CellRect?
    var zIndex: Double
    var childCount: Int
    var semanticRole: SemanticRole
    var layoutMetadata: LayoutMetadata
    var drawMetadata: DrawMetadataSignature
    var drawEffects: DrawEffects
    var surfaceComposition: SurfaceCompositionMetadata
    var semanticMetadata: SemanticMetadata
    var lifecycleMetadata: LifecycleMetadata
    var drawPayload: DrawPayload
    var layoutBehavior: LayoutBehavior
    var isTransient: Bool
    var matchedGeometry: MatchedGeometryConfig?
    var lazyChildScrollEstimates: [LazyChildScrollEstimate]?

    init(_ node: PlacedNode) {
      identity = node.identity
      kind = node.kind
      environmentSnapshot = node.environmentSnapshot
      bounds = node.bounds
      contentBounds = node.contentBounds
      clipBounds = node.clipBounds
      zIndex = node.zIndex
      childCount = node.children.count
      semanticRole = node.semanticRole
      layoutMetadata = node.layoutMetadata
      drawMetadata = .init(node.drawMetadata)
      drawEffects = node.drawEffects
      surfaceComposition = node.surfaceComposition
      semanticMetadata = node.semanticMetadata
      lifecycleMetadata = node.lifecycleMetadata
      drawPayload = node.drawPayload
      layoutBehavior = node.layoutBehavior
      isTransient = node.isTransient
      matchedGeometry = node.matchedGeometry
      lazyChildScrollEstimates = node.lazyChildScrollEstimates
    }
  }

  private struct DrawMetadataSignature: Equatable, Sendable {
    var heavyFields: DrawMetadata.HeavyFields
    var clipsToBounds: Bool
    var clipIdentifier: String?
    var compositingHint: String?
    var imagePreference: String?
    var ruleStackAxis: Axis?

    init(_ metadata: DrawMetadata) {
      heavyFields = metadata.heavyFields.value
      clipsToBounds = metadata.clipsToBounds
      clipIdentifier = metadata.clipIdentifier
      compositingHint = metadata.compositingHint
      imagePreference = metadata.imagePreference
      ruleStackAxis = metadata.ruleStackAxis
    }
  }

  /// Whether the two placed subtrees are byte-equivalent for phase reuse:
  /// every positional node pair matches on the full `NodeSignature` field
  /// set and every node on both sides supports retained extraction
  /// (`.canvas`/`.foreignSurface`/custom layout never prove equivalence —
  /// their draw products are not value-comparable). First difference wins.
  package static func subtreesIdentical(
    _ current: PlacedNode,
    _ previous: PlacedNode
  ) -> Bool {
    var stack: [(PlacedNode, PlacedNode)] = [(current, previous)]
    while let (currentNode, previousNode) = stack.popLast() {
      guard currentNode.supportsRetainedPhaseExtraction,
        previousNode.supportsRetainedPhaseExtraction,
        NodeSignature(currentNode) == NodeSignature(previousNode)
      else {
        return false
      }
      // The signature compare above pins equal child counts, so positional
      // pairing is total.
      for pair in zip(currentNode.children, previousNode.children) {
        stack.append(pair)
      }
    }
    return true
  }
}

package struct RetainedSemanticExtractionInput: Sendable {
  package var previousSnapshot: SemanticSnapshot
  package var proof: RetainedPhaseExtractionProof

  package init(
    previousSnapshot: SemanticSnapshot,
    proof: RetainedPhaseExtractionProof
  ) {
    self.previousSnapshot = previousSnapshot
    self.proof = proof
  }
}

package struct RetainedDrawExtractionInput: Sendable {
  package var previousDraw: DrawNode
  package var previousDrawByNodeID: [ViewNodeID: DrawNode]
  package var proof: RetainedPhaseExtractionProof

  package init(
    previousDraw: DrawNode,
    previousDrawByNodeID: [ViewNodeID: DrawNode] = [:],
    proof: RetainedPhaseExtractionProof
  ) {
    self.previousDraw = previousDraw
    self.previousDrawByNodeID = previousDrawByNodeID
    self.proof = proof
  }

  package func previousDrawNode(for node: PlacedNode) -> DrawNode? {
    if let viewNodeID = node.viewNodeID,
      previousDraw.viewNodeID == viewNodeID
    {
      return previousDraw
    }
    if previousDraw.identity == node.identity {
      return previousDraw
    }
    if let viewNodeID = node.viewNodeID {
      return previousDrawByNodeID[viewNodeID]
    }
    return nil
  }
}

extension SemanticSnapshot {
  package var retainedExtractionProduct: Self {
    var snapshot = self
    snapshot.accessibilityAnnouncements = []
    return snapshot
  }
}

extension PlacedNode {
  fileprivate var supportsRetainedPhaseExtraction: Bool {
    drawPayload.supportsRetainedPhaseExtraction
      && layoutBehavior.supportsRetainedPhaseExtraction
  }
}

extension DrawPayload {
  fileprivate var supportsRetainedPhaseExtraction: Bool {
    switch self {
    case .canvas, .foreignSurface:
      return false
    default:
      return true
    }
  }
}

extension LayoutBehavior {
  fileprivate var supportsRetainedPhaseExtraction: Bool {
    if case .custom = self {
      return false
    }
    return true
  }
}
