package struct ViewNodeRuntimeKey<Suffix: Hashable & Sendable>: Hashable, Sendable,
  CustomStringConvertible
{
  package var ownerNodeID: ViewNodeID?
  package var suffix: Suffix

  package init(
    ownerNodeID: ViewNodeID?,
    suffix: Suffix
  ) {
    self.ownerNodeID = ownerNodeID
    self.suffix = suffix
  }

  package var description: String {
    let ownerDescription = ownerNodeID.map(\.description) ?? "unowned"
    return "\(ownerDescription)#\(String(describing: suffix))"
  }
}
