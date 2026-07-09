/// Grouped metadata for lifecycle properties of a resolved node.
public struct NodeLifecycleInfo: Equatable, Sendable {
  public var lifecycleMetadata: LifecycleMetadata

  public init(
    lifecycleMetadata: LifecycleMetadata = .init()
  ) {
    self.lifecycleMetadata = lifecycleMetadata
  }

  public var isEmpty: Bool {
    lifecycleMetadata.isEmpty
  }
}

extension ResolvedNode {
  /// Grouped lifecycle metadata for this node.
  public var lifecycleInfo: NodeLifecycleInfo {
    get {
      NodeLifecycleInfo(
        lifecycleMetadata: lifecycleMetadata
      )
    }
    set {
      lifecycleMetadata = newValue.lifecycleMetadata
    }
  }
}
