public import SwiftTUICore

@MainActor
public protocol ViewModifier {
  associatedtype Body: View
  typealias Content = ViewModifierContent<Self>

  @ViewBuilder
  func body(content: Content) -> Body
}

extension ViewModifier where Body == Never {
  public func body(content _: Content) -> Body {
    fatalError("\(Self.self) is a primitive modifier and does not expose a composed body.")
  }
}

@MainActor
package struct ModifierContentInputs<Base: View> {
  package let base: Base
  package let authoringScope: CapturedSubviewScope?

  private func applyAuthoringContext<Result>(
    _ body: () -> Result
  ) -> Result {
    withAuthoringContext(authoringScope?.authoringContext) {
      body()
    }
  }

  private func applyOwnedAuthoringContext<Result>(
    in context: ResolveContext,
    _ body: () -> Result
  ) -> Result {
    let rebased = authoringScope?.authoringContext.map { scope in
      AuthoringContext(
        viewIdentity: context.identity,
        structuralIdentity: context.structuralPath.identityProjection,
        structuralPath: context.structuralPath,
        focusedValues: context.focusedValues,
        viewNode: ViewNodeContext.current,
        ownerNodeID: ViewNodeContext.current?.viewNodeID ?? scope.ownerNodeID,
        stateGraphScope: ViewNodeContext.current?.ownerGraph.map(StateGraphScopeID.init)
          ?? scope.stateGraphScope,
        ordinalTracker: scope.ordinalTracker
      )
    }
    return withAuthoringContext(rebased) {
      body()
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyAuthoringContext {
      let erased: Any = base
      if let resolvable = erased as? any ResolvableView {
        return resolvable.resolveElements(in: context)
      }
      return resolveViewElements(base, in: context)
    }
  }

  /// Runs a user-authored closure carried by the modifier *value* under the
  /// authoring scope captured when the modifier was constructed (the
  /// enclosing body). Dynamic-property reads inside such closures must reach
  /// the authoring owner's state slots: the ambient context during a
  /// modifier's resolve names the node currently evaluating, which — below a
  /// child node boundary, or on a selective re-resolution that never re-ran
  /// the authoring body — is NOT the closure's owner, so an unwrapped read
  /// would seed and then forever serve a foreign node's slot (the
  /// stale-`@State`-binding family; `HandlerDescriptorIntake`'s
  /// construction-scope preference is the dispatch-side twin of this seam).
  /// A modifier with no captured scope leaves the ambient context untouched.
  package func withAuthoredClosureScope<Result>(
    _ body: () -> Result
  ) -> Result {
    guard let scope = authoringScope?.authoringContext else {
      return body()
    }
    return withAuthoringContext(scope) {
      body()
    }
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    applyAuthoringContext {
      resolveView(base, in: context)
    }
  }

  package func resolveOwned(in context: ResolveContext) -> ResolvedNode {
    applyOwnedAuthoringContext(in: context) {
      var resolved = normalizeResolvedElements(
        resolveViewElements(base, in: context),
        in: context
      )
      assignEntityIdentityOccurrences(to: &resolved._storedChildren)
      resolved.structuralPath = context.structuralPath
      return resolved
    }
  }
}

@MainActor
package protocol PrimitiveViewModifier: ViewModifier where Body == Never {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode]
}

public struct ViewModifierContent<Modifier: ViewModifier>: PrimitiveView, ResolvableView {
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]

  package init<Base: View>(
    base: Base,
    authoringScope: CapturedSubviewScope?
  ) {
    let inputs = ModifierContentInputs(
      base: base,
      authoringScope: authoringScope
    )
    resolveElementsClosure = { context in
      inputs.resolveElements(in: context)
    }
  }

  public var body: Never {
    fatalError("ViewModifier.Content is an opaque modifier-content carrier.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveElementsClosure(context)
  }
}

public struct ModifiedContent<Content, Modifier> {
  public var content: Content
  public var modifier: Modifier
  package var authoringScope: CapturedSubviewScope

  @MainActor
  public init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
    authoringScope = makeCapturedSubviewScope()
  }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
  public var body: some View {
    modifier.body(
      content: ViewModifierContent(
        base: content,
        authoringScope: authoringScope
      )
    )
  }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
  public func body(content: ViewModifierContent<Self>) -> some View {
    content
      .modifier(self.content)
      .modifier(modifier)
  }
}

extension ModifiedContent: ResolvableView where Content: View, Modifier: PrimitiveViewModifier {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let authoringContext = dynamicPropertyAuthoringContext(for: context)
    let inputs = ModifierContentInputs(
      base: content,
      authoringScope: authoringScope
    )
    return withAuthoringContext(authoringContext) {
      modifier.resolve(content: inputs, in: context)
    }
  }
}

extension ModifiedContent: EntityRouteProvidingView
where Content: View, Modifier: ViewModifier {
  package func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity? {
    // A `.id(_:)` sets the identity of the *entire* modified view up to that
    // point, so modifiers applied outside it (e.g. `.task`, `.onAppear`) belong
    // to the same entity and must resolve their view node through the same
    // entity route. When this wrapper's own modifier does not provide the route,
    // forward the one carried by the wrapped content so the outer wrappers bind
    // to the entity node in the same render as an `.id` rebind instead of the
    // departing structural-slot node.
    if let entityModifier = modifier as? any EntityRouteProvidingModifier {
      return entityModifier.resolveEntityRouteIdentity(in: context)
    }
    if let entityContent = content as? any EntityRouteProvidingView {
      return entityContent.resolveEntityRouteIdentity(in: context)
    }
    return nil
  }

  package var providesHostEscapingEntityRoute: Bool {
    // Mirrors the forwarding cascade above: escaping-ness is a property of
    // whichever provider actually supplies the route.
    if let entityModifier = modifier as? any EntityRouteProvidingModifier {
      return entityModifier.providesHostEscapingEntityRoute
    }
    if let entityContent = content as? any EntityRouteProvidingView {
      return entityContent.providesHostEscapingEntityRoute
    }
    return false
  }
}

extension ModifiedContent: Sendable where Content: Sendable, Modifier: Sendable {}

extension ModifiedContent: Identifiable where Content: Identifiable {
  public typealias ID = Content.ID

  public var id: Content.ID {
    content.id
  }
}

extension ModifiedContent: ActionScope where Content: ActionScope {}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {
  public static func == (
    lhs: ModifiedContent<Content, Modifier>,
    rhs: ModifiedContent<Content, Modifier>
  ) -> Bool {
    lhs.content == rhs.content
      && lhs.modifier == rhs.modifier
  }
}

extension ModifiedContent: Animatable where Content: Animatable, Modifier: Animatable {
  public typealias AnimatableData = AnimatablePair<Content.AnimatableData, Modifier.AnimatableData>

  public var animatableData: AnimatableData {
    get {
      .init(content.animatableData, modifier.animatableData)
    }
    set {
      content.animatableData = newValue.first
      modifier.animatableData = newValue.second
    }
  }
}

extension View {
  public func modifier<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M> {
    ModifiedContent(
      content: self,
      modifier: modifier
    )
  }
}

extension ViewModifier {
  public func concat<M: ViewModifier>(
    _ modifier: M
  ) -> ModifiedContent<Self, M> {
    ModifiedContent(
      content: self,
      modifier: modifier
    )
  }
}
