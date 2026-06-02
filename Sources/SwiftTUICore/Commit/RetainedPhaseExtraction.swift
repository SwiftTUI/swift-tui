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

package struct RetainedPhaseExtractionSignature: Equatable, Sendable {
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

  private var nodes: [NodeSignature]

  package static func make(
    from placed: PlacedNode
  ) -> Self? {
    var nodes: [NodeSignature] = []
    nodes.reserveCapacity(placed.subtreeNodeCount)
    var stack: [PlacedNode] = [placed]

    while let node = stack.popLast() {
      guard node.supportsRetainedPhaseExtraction else {
        return nil
      }
      nodes.append(
        NodeSignature(
          identity: node.identity,
          kind: node.kind,
          environmentSnapshot: node.environmentSnapshot,
          bounds: node.bounds,
          contentBounds: node.contentBounds,
          clipBounds: node.clipBounds,
          zIndex: node.zIndex,
          childCount: node.children.count,
          semanticRole: node.semanticRole,
          layoutMetadata: node.layoutMetadata,
          drawMetadata: .init(node.drawMetadata),
          drawEffects: node.drawEffects,
          surfaceComposition: node.surfaceComposition,
          semanticMetadata: node.semanticMetadata,
          lifecycleMetadata: node.lifecycleMetadata,
          drawPayload: node.drawPayload,
          layoutBehavior: node.layoutBehavior,
          isTransient: node.isTransient,
          matchedGeometry: node.matchedGeometry
        )
      )
      for child in node.children.reversed() {
        stack.append(child)
      }
    }

    return Self(nodes: nodes)
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
  package var previousDrawByIdentity: [Identity: DrawNode]
  package var proof: RetainedPhaseExtractionProof

  package init(
    previousDraw: DrawNode,
    previousDrawByIdentity: [Identity: DrawNode] = [:],
    proof: RetainedPhaseExtractionProof
  ) {
    self.previousDraw = previousDraw
    self.previousDrawByIdentity = previousDrawByIdentity
    self.proof = proof
  }

  package func previousDrawNode(for identity: Identity) -> DrawNode? {
    if previousDraw.identity == identity {
      return previousDraw
    }
    return previousDrawByIdentity[identity]
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
