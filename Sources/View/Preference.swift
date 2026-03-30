public import Core

extension View {
  /// Sets a value for the supplied preference key on this view subtree.
  public func preference<Key: PreferenceKey>(
    key: Key.Type = Key.self,
    value: Key.Value
  ) -> some View {
    PreferenceWritingModifier<Key, Self>(
      content: self,
      value: value
    )
  }

  /// Applies an in-place transformation to the reduced preference value.
  public func transformPreference<Key: PreferenceKey>(
    _ key: Key.Type = Key.self,
    _ transform: @escaping (inout Key.Value) -> Void
  ) -> some View {
    PreferenceTransformModifier<Key, Self>(
      content: self,
      transform: transform
    )
  }

  /// Performs an action when a preference value changes across rendered frames.
  public func onPreferenceChange<Key: PreferenceKey>(
    _ key: Key.Type = Key.self,
    perform action: @escaping @MainActor (Key.Value) -> Void
  ) -> some View where Key.Value: Equatable {
    PreferenceChangeModifier<Key, Self>(
      content: self,
      action: action
    )
  }

  /// Reads the reduced preference value and applies a background derived from it.
  public func backgroundPreferenceValue<Key: PreferenceKey, Content: View>(
    _ key: Key.Type,
    alignment: Alignment = .center,
    @ViewBuilder _ transform: @escaping (Key.Value) -> Content
  ) -> some View {
    PreferenceBackgroundValueModifier<Self, Key>(
      base: self,
      alignment: alignment,
      transform: transform
    )
  }

  /// Reads the reduced preference value and applies an overlay derived from it.
  public func overlayPreferenceValue<Key: PreferenceKey, Content: View>(
    _ key: Key.Type,
    alignment: Alignment = .center,
    @ViewBuilder _ transform: @escaping (Key.Value) -> Content
  ) -> some View {
    PreferenceOverlayValueModifier<Self, Key>(
      base: self,
      alignment: alignment,
      transform: transform
    )
  }
}

private struct PreferenceWritingModifier<Key: PreferenceKey, Content: View>: View, ResolvableView {
  var content: Content
  var value: Key.Value

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(Key.self, value: value)
    return [node]
  }
}

private struct PreferenceTransformModifier<Key: PreferenceKey, Content: View>: View, ResolvableView
{
  var content: Content
  var transform: (inout Key.Value) -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.transform(
      Key.self,
      transform
    )
    return [node]
  }
}

private struct PreferenceChangeModifier<Key: PreferenceKey, Content: View>: View, ResolvableView
where Key.Value: Equatable {
  var content: Content
  let action: @MainActor (Key.Value) -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let dynamicPropertyScope = currentDynamicPropertyScope()
    context.localPreferenceObservationRegistry?.register(
      identity: node.identity,
      key: Key.self,
      value: node.preferenceValues[Key.self]
    ) { value in
      withDynamicPropertyScope(dynamicPropertyScope) {
        action(value)
      }
    }
    return [node]
  }
}

// AnyView policy: preference reader modifiers store transformed authored content
// as scoped type erasure so later resolve passes keep the original property scope.
private struct PreferenceOverlayValueModifier<Base: View, Key: PreferenceKey>: View,
  ResolvableView
{
  var base: Base
  var alignment: Alignment
  private let transform: (Key.Value) -> AnyView

  init<Overlay: View>(
    base: Base,
    alignment: Alignment,
    @ViewBuilder transform: @escaping (Key.Value) -> Overlay
  ) {
    self.base = base
    self.alignment = alignment
    let authoringScope = currentDynamicPropertyScope()
    self.transform = { value in
      scopedAnyView(authoringScope: authoringScope) {
        transform(value)
      }
    }
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseNode = base.resolve(in: context.child(component: .named("base")))
    let overlayView = context.trackingObservableAccess {
      transform(baseNode.preferenceValues[Key.self])
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

// AnyView policy: preference reader modifiers store transformed authored content
// as scoped type erasure so later resolve passes keep the original property scope.
private struct PreferenceBackgroundValueModifier<Base: View, Key: PreferenceKey>: View,
  ResolvableView
{
  var base: Base
  var alignment: Alignment
  private let transform: (Key.Value) -> AnyView

  init<Background: View>(
    base: Base,
    alignment: Alignment,
    @ViewBuilder transform: @escaping (Key.Value) -> Background
  ) {
    self.base = base
    self.alignment = alignment
    let authoringScope = currentDynamicPropertyScope()
    self.transform = { value in
      scopedAnyView(authoringScope: authoringScope) {
        transform(value)
      }
    }
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseNode = base.resolve(in: context.child(component: .named("base")))
    let backgroundView = context.trackingObservableAccess {
      transform(baseNode.preferenceValues[Key.self])
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
