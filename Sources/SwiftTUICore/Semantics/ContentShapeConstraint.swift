/// Marks authored content shapes as constraints on descendant pointer targets.
/// Internal controls can still override their own target without clipping children.
private enum ContentShapeConstraintKey {}

extension LayoutMetadata {
  package var constrainsDescendantPointerTargets: Bool {
    layoutValue(for: ObjectIdentifier(ContentShapeConstraintKey.self), as: Bool.self) ?? false
  }

  package func constrainingDescendantPointerTargets() -> Self {
    settingLayoutValue(
      true, for: ObjectIdentifier(ContentShapeConstraintKey.self),
      debugName: "content-shape-constraint", debugValue: "true")
  }
}
