/// A stored property of a view (or of another dynamic property) that the
/// framework updates before each body evaluation.
///
/// Conform a custom property wrapper to `DynamicProperty` to make it a
/// first-class participant in view evaluation: the framework discovers
/// conforming stored properties, gives wrappers composed *inside* them
/// distinct per-instance state storage, and calls ``update()`` under the
/// enclosing view's authoring scope before the body runs.
///
/// Compose the built-in wrappers (`@State`, `@Environment`, `@Binding`, …)
/// inside a conforming wrapper rather than storing mutable values directly:
/// `update()` runs on a copy of the enclosing view's value, so mutations to
/// plain stored properties do not persist — state that must survive between
/// evaluations belongs in composed reference-backed storage. See the
/// "Custom dynamic properties" article in the `SwiftTUIViews` documentation
/// catalog for the full authoring contract.
public protocol DynamicProperty {
  /// Refreshes the property's state before the enclosing body evaluates.
  ///
  /// The framework calls this on every body evaluation of the enclosing
  /// view, after nested dynamic properties have been updated and with the
  /// enclosing view's authoring scope installed. The default implementation
  /// does nothing.
  @MainActor
  mutating func update()
}

extension DynamicProperty {
  @MainActor
  public mutating func update() {}
}
