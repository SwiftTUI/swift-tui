/// A detached nonmodal surface remains next to its source in keyboard order.
/// Paint order and pointer hit order are independent of this placement hint.
private enum FocusOrderAnchorKey {}

extension LayoutMetadata {
  package var focusOrderAnchor: Identity? {
    layoutValue(for: ObjectIdentifier(FocusOrderAnchorKey.self), as: Identity.self)
  }

  package func anchoringFocusOrder(after identity: Identity) -> Self {
    settingLayoutValue(
      identity, for: ObjectIdentifier(FocusOrderAnchorKey.self),
      debugName: "focus-order-anchor", debugValue: identity.path)
  }
}
