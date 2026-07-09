/// Grouped metadata for semantic properties of a resolved node.
public struct NodeSemanticInfo: Equatable, Sendable {
  public var semanticMetadata: SemanticMetadata

  public init(
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    self.semanticMetadata = semanticMetadata
  }
}

extension ResolvedNode {
  /// Grouped semantic metadata for this node.
  public var semanticInfo: NodeSemanticInfo {
    get {
      NodeSemanticInfo(
        semanticMetadata: semanticMetadata
      )
    }
    set {
      semanticMetadata = newValue.semanticMetadata
    }
  }
}
