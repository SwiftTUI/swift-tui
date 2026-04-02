package struct ChildDescriptor: Equatable, Hashable, Sendable {
  package var typeIdentity: String
  package var explicitID: String?

  package init(
    typeIdentity: String,
    explicitID: String? = nil
  ) {
    self.typeIdentity = typeIdentity
    self.explicitID = explicitID
  }

  package init(resolvedNode: ResolvedNode) {
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
