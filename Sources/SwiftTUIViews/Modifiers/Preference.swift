public import SwiftTUICore

extension View {
  /// Sets a value for the supplied preference key on this view subtree.
  public func preference<Key: PreferenceKey>(
    key: Key.Type = Key.self,
    value: Key.Value
  ) -> some View {
    modifier(
      PreferenceWritingModifier<Key>(
        value: value
      )
    )
  }

  /// Applies an in-place transformation to the reduced preference value.
  public func transformPreference<Key: PreferenceKey>(
    _ key: Key.Type = Key.self,
    _ transform: @escaping (inout Key.Value) -> Void
  ) -> some View {
    modifier(
      PreferenceTransformModifier<Key>(
        transform: transform
      )
    )
  }

  /// Stores a geometry anchor preference for the modified view.
  public func anchorPreference<Key: PreferenceKey, Value: Sendable>(
    key: Key.Type = Key.self,
    value: AnchorSource<Value>,
    transform: @escaping (Anchor<Value>) -> Key.Value
  ) -> some View {
    modifier(
      AnchorPreferenceWritingModifier<Key, Value>(
        source: value,
        transform: transform
      )
    )
  }

  /// Applies an in-place transformation using a geometry anchor for the
  /// modified view.
  public func transformAnchorPreference<Key: PreferenceKey, Value: Sendable>(
    _ key: Key.Type = Key.self,
    value: AnchorSource<Value>,
    transform: @escaping (inout Key.Value, Anchor<Value>) -> Void
  ) -> some View {
    modifier(
      AnchorPreferenceTransformModifier<Key, Value>(
        source: value,
        transform: transform
      )
    )
  }

  /// Performs an action when a preference value changes across rendered frames.
  public func onPreferenceChange<Key: PreferenceKey>(
    _ key: Key.Type = Key.self,
    perform action: @escaping @MainActor (Key.Value) -> Void
  ) -> some View where Key.Value: Equatable {
    modifier(
      PreferenceChangeModifier<Key>(
        action: action
      )
    )
  }

  /// Reads the reduced preference value and applies a background derived from it.
  public func backgroundPreferenceValue<Key: PreferenceKey, Content: View>(
    _ key: Key.Type,
    alignment: Alignment = .center,
    @ViewBuilder _ transform: @escaping (Key.Value) -> Content
  ) -> some View {
    modifier(
      PreferenceBackgroundValueModifier<Key, Content>(
        alignment: alignment,
        transform: transform
      )
    )
  }

  /// Reads the reduced preference value and applies an overlay derived from it.
  public func overlayPreferenceValue<Key: PreferenceKey, Content: View>(
    _ key: Key.Type,
    alignment: Alignment = .center,
    @ViewBuilder _ transform: @escaping (Key.Value) -> Content
  ) -> some View {
    modifier(
      PreferenceOverlayValueModifier<Key, Content>(
        alignment: alignment,
        transform: transform
      )
    )
  }
}

public struct AnchorPreferenceWritingModifier<Key: PreferenceKey, Value: Sendable>:
  PrimitiveViewModifier
{
  var source: AnchorSource<Value>
  var transform: (Anchor<Value>) -> Key.Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let anchor = Anchor<Value>(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      kind: source.kind
    )
    node.preferenceValues.merge(
      Key.self,
      value: content.withAuthoredClosureScope {
        transform(anchor)
      }
    )
    return [node]
  }
}

public struct AnchorPreferenceTransformModifier<Key: PreferenceKey, Value: Sendable>:
  PrimitiveViewModifier
{
  var source: AnchorSource<Value>
  var transform: (inout Key.Value, Anchor<Value>) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let anchor = Anchor<Value>(
      viewNodeID: node.viewNodeID,
      identity: node.identity,
      kind: source.kind
    )
    node.preferenceValues.transform(Key.self) { value in
      content.withAuthoredClosureScope {
        transform(&value, anchor)
      }
    }
    return [node]
  }
}

public struct PreferenceWritingModifier<Key: PreferenceKey>: PrimitiveViewModifier {
  var value: Key.Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(Key.self, value: value)
    return [node]
  }
}

public struct PreferenceTransformModifier<Key: PreferenceKey>: PrimitiveViewModifier {
  var transform: (inout Key.Value) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.transform(Key.self) { value in
      content.withAuthoredClosureScope {
        transform(&value)
      }
    }
    return [node]
  }
}

public struct PreferenceChangeModifier<Key: PreferenceKey>: PrimitiveViewModifier
where
  Key.Value: Equatable
{
  let action: @MainActor (Key.Value) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let intake = HandlerDescriptorIntake(context: context)
    intake.registerPreferenceObservation(
      identity: node.identity,
      key: Key.self,
      value: node.preferenceValues[Key.self],
      action: action
    )
    return [node]
  }
}

public struct PreferenceOverlayValueModifier<Key: PreferenceKey, Overlay: View>:
  PrimitiveViewModifier
{
  var alignment: Alignment
  private let transform: (Key.Value) -> Overlay
  private let authoringScope: AuthoringContext?

  init(
    alignment: Alignment,
    @ViewBuilder transform: @escaping (Key.Value) -> Overlay
  ) {
    self.alignment = alignment
    self.transform = transform
    authoringScope = currentAuthoringContext()
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let baseNode = content.resolve(in: context.child(component: .named("base")))
    let overlayView = withAuthoringContext(authoringScope) {
      context.trackingObservableAccess {
        transform(baseNode.preferenceValues[Key.self])
      }
    }
    // The overlay derives from the base subtree's preference fold — data the
    // invalidation tracker does not see, so the overlay subtree is never in
    // any invalidation cone of its own. Reaching this resolve means the
    // wrapper recomputed and the fold may have changed; retained reuse below
    // here would keep serving content computed from the previous fold.
    var overlayContext = context.child(component: .named("overlay"))
    overlayContext.withinChurnedSubtree = true
    let overlayNode = overlayView.resolve(in: overlayContext)
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Overlay"),
        children: [baseNode, overlayNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .decoration(primaryIndex: 0, alignment: alignment)
      )
    ]
  }
}

public struct PreferenceBackgroundValueModifier<Key: PreferenceKey, Background: View>:
  PrimitiveViewModifier
{
  var alignment: Alignment
  private let transform: (Key.Value) -> Background
  private let authoringScope: AuthoringContext?

  init(
    alignment: Alignment,
    @ViewBuilder transform: @escaping (Key.Value) -> Background
  ) {
    self.alignment = alignment
    self.transform = transform
    authoringScope = currentAuthoringContext()
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let baseNode = content.resolve(in: context.child(component: .named("base")))
    let backgroundView = withAuthoringContext(authoringScope) {
      context.trackingObservableAccess {
        transform(baseNode.preferenceValues[Key.self])
      }
    }
    // Mirrors the overlay variant: the background derives from the fold, so
    // reuse below here must not outlive the wrapper's recompute.
    var backgroundContext = context.child(component: .named("background"))
    backgroundContext.withinChurnedSubtree = true
    let backgroundNode = backgroundView.resolve(in: backgroundContext)
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Background"),
        children: [backgroundNode, baseNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .decoration(primaryIndex: 1, alignment: alignment)
      )
    ]
  }
}
