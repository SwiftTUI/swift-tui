public import Core

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
    node.preferenceValues.transform(
      Key.self,
      transform
    )
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
    let dynamicPropertyScope = currentAuthoringContext()
    context.localPreferenceObservationRegistry?.register(
      identity: node.identity,
      key: Key.self,
      value: node.preferenceValues[Key.self]
    ) { value in
      withAuthoringContext(dynamicPropertyScope) {
        action(value)
      }
    }
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
    let overlayNode = overlayView.resolve(in: context.child(component: .named("overlay")))
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
    let backgroundNode = backgroundView.resolve(
      in: context.child(component: .named("background"))
    )
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
