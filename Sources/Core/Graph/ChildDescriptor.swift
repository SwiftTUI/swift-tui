package struct ChildDescriptor: Equatable, Hashable, Sendable {
  package var identity: Identity
  package var typeIdentity: String
  package var explicitID: String?

  package init(
    identity: Identity,
    typeIdentity: String,
    explicitID: String? = nil
  ) {
    self.identity = identity
    self.typeIdentity = typeIdentity
    self.explicitID = explicitID
  }

  package init(resolvedNode: ResolvedNode) {
    identity = resolvedNode.identity
    typeIdentity =
      switch resolvedNode.kind {
      case .root:
        "root"
      case .scene(let name):
        "scene:\(name)"
      case .view(let name):
        "view:\(name)"
      }
    explicitID = Self.explicitID(from: resolvedNode.identity)
  }

  private static func explicitID(
    from identity: Identity
  ) -> String? {
    guard let lastComponent = identity.lastComponent else {
      return nil
    }
    guard lastComponent.hasPrefix("ID[") else {
      return nil
    }
    return lastComponent
  }
}
