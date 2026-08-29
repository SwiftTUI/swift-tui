public import SwiftTUICore

/// A reusable transformation applied to a view's content.
///
/// A modifier is a value type — a struct or an enum — for the same reason a
/// ``View`` is: its composed body evaluates through a private per-mount copy
/// the state passes bind.
@MainActor
public protocol ViewModifier {
  associatedtype Body: View
  typealias Content = ViewModifierContent<Self>

  @ViewBuilder
  func body(content: Content) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _viewModifierValueTypeWitness: Void { get }
}

extension ViewModifier {
  @_documentation(visibility: internal)
  public static var _viewModifierValueTypeWitness: Void { () }
}

extension ViewModifier where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI view modifiers must be value types (a struct or an enum); a class cannot conform to ViewModifier"
  )
  public static var _viewModifierValueTypeWitness: Void { () }
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
    // An ambient context carrying a per-mount rebase of THIS chain's captured
    // enclosing scope (an outer identity modifier's `resolveOwned`) must stay
    // in effect: the construction capture is per view VALUE, so reinstalling
    // it under a value mounted at several identities would collapse every
    // mount's `@State` onto the one captured owner (stress state identity
    // 004). The origin check keeps this narrow — an ambient rebased from a
    // DIFFERENT scope (foreign capture hosting) still yields to the capture.
    if let captured = authoringScope?.authoringContext {
      if let ambient = currentAuthoringContext(),
        let origin = ambient.rebasedFromOwnerNodeID,
        origin == captured.ownerNodeID,
        ambient.ownerNodeID != captured.ownerNodeID
      {
        return body()
      }
      return withAuthoringContext(captured) {
        body()
      }
    }
    return withAuthoringContext(nil) {
      body()
    }
  }

  package func withDynamicPropertyAuthoringScope<Result>(
    in context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?,
    _ body: () -> Result
  ) -> Result {
    applyAuthoringContext {
      let scope = dynamicPropertyAuthoringContext(
        for: context,
        current: currentAuthoringContext(),
        viewNode: graphNode
      )
      return withAuthoringContext(scope, body)
    }
  }

  package func preparedDynamicPropertyContext(
    in fallback: ResolveContext
  ) -> ResolveContext? {
    ForwardedDynamicPropertyPreparationScope.preparedContext(
      for: base,
      fallback: fallback,
      graphNode: ViewNodeContext.current
    )
  }

  private func contentResolveContext(
    in context: ResolveContext
  ) -> ResolveContext {
    if let prepared = preparedDynamicPropertyContext(in: context) {
      return prepared
    }
    // Default/structural/entity-routing modifiers cannot prepare their base
    // at the outer wrapper: only this actual content edge knows its node and
    // path. Prepare the whole forwarded value here so a base that is itself a
    // DynamicProperty receives its root update as well as its nested updates,
    // then let the central resolver consume that exact preparation.
    _ = prepareDynamicProperties(in: context)
    return context
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
        stateOwnerHandle: ViewNodeContext.current?.stateOwnerHandle ?? scope.stateOwnerHandle,
        stateGraphScope: ViewNodeContext.current?.ownerGraph.map(StateGraphScopeID.init)
          ?? scope.stateGraphScope,
        ordinalTracker: scope.ordinalTracker,
        rebasedFromOwnerNodeID: scope.ownerNodeID
      )
    }
    return withAuthoringContext(rebased) {
      body()
    }
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    applyAuthoringContext {
      // The actual content edge owns the central update/evaluation seam. A
      // certified same-node producer may already have prepared this exact
      // context before its own reuse door; every other edge evaluates here.
      let resolved = resolveView(
        base,
        in: contentResolveContext(in: context)
      )
      return consumeDeclaredChild(
        resolved,
        resolvedUnder: context.identity,
        in: context.viewGraph,
        policy: .declaredBuilder
      )
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
      resolveView(
        base,
        in: contentResolveContext(in: context)
      )
    }
  }

  package func resolveOwned(in context: ResolveContext) -> ResolvedNode {
    applyOwnedAuthoringContext(in: context) {
      // Identity modifiers are structural content edges too. Going through
      // the central resolver is what lets an entity-routed base update once
      // at its routed owner instead of being guessed at the outer wrapper.
      var resolved = resolveView(
        base,
        in: contentResolveContext(in: context)
      )
      resolved.structuralPath = context.structuralPath
      return resolved
    }
  }

  package func prepareDynamicProperties(
    in context: ResolveContext
  ) -> DynamicPropertyUpdateResult {
    let routeIdentity = entityRouteIdentity(for: base, in: context)
    let graphNode: SwiftTUICore.ViewNode?
    if let routeIdentity,
      let routed = context.viewGraph?.nodeForEntityIdentity(routeIdentity)
    {
      graphNode = routed
    } else {
      graphNode = context.viewGraph?.prepareDynamicPropertyUpdate(
        identity: context.identity,
        entityIdentity: routeIdentity
      )
    }
    let forwardedContext = AdditionalDynamicPropertyUpdateContext(
      resolveContext: context,
      graphNode: graphNode
    )
    let result = EnvironmentValuesStorage.binding(context.environmentValues) {
      ViewNodeContext.withCurrentValue(graphNode) {
        withDynamicPropertyAuthoringScope(
          in: context,
          graphNode: graphNode
        ) {
          runForwardedDynamicPropertyUpdates(on: base, in: forwardedContext)
        }
      }
    }
    ForwardedDynamicPropertyPreparationScope.record(
      base,
      context: context,
      graphNode: graphNode,
      result: result
    )
    return result
  }
}

@MainActor
package protocol PrimitiveViewModifier: ViewModifier where Body == Never {
  func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode]

  /// Returns the exact same-node context in which this modifier will resolve
  /// its content, when the modifier can prove that mapping before `resolve`.
  ///
  /// `nil` is the conservative default. Structural, entity-routing, and
  /// arbitrary-context modifiers then deny their outer reuse door and let the
  /// actual nested central resolve own the content update and lease.
  func dynamicPropertyContentPreparation<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveContext?
}

extension PrimitiveViewModifier {
  package func dynamicPropertyContentPreparation<Base: View>(
    content _: ModifierContentInputs<Base>,
    in _: ResolveContext
  ) -> ResolveContext? {
    nil
  }
}

public struct ViewModifierContent<Modifier: ViewModifier>: PrimitiveView, ResolvableView {
  private let resolveElementsClosure: @MainActor (ResolveContext) -> [ResolvedNode]
  private let updateDynamicPropertiesClosure:
    @MainActor (ResolveContext) -> DynamicPropertyUpdateResult

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
    updateDynamicPropertiesClosure = { context in
      inputs.prepareDynamicProperties(in: context)
    }
  }

  public var body: Never {
    fatalError("ViewModifier.Content is an opaque modifier-content carrier.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // A composed modifier may place this carrier at any point in its body (or
    // omit it). `View.resolveBody` calls ResolvableView bodies directly, so
    // this carrier itself is the only exact pre-content seam: prepare here,
    // then let the nested central resolve consume the result.
    _ = updateDynamicPropertiesClosure(context)
    return resolveElementsClosure(context)
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
    // Capture-bind pass (plan 2026-08-20-001): the modifier is a forwarded
    // payload — `updateAdditionalDynamicProperties` runs its `@State` as its
    // own root with root-relative paths — so it binds as its own root here,
    // at the seam its body runs, under the same ambient scope. Binding it as
    // a nested field of this wrapper would append a field path the update
    // pass never claims (the outer walk excludes fields 0/1 for the same
    // reason).
    return bindingForwardedDynamicPropertyCaptures(modifier).body(
      content: ViewModifierContent(
        base: content,
        authoringScope: authoringScope
      )
    )
  }
}

extension ModifiedContent: AdditionalDynamicPropertyUpdating
where Content: View, Modifier: ViewModifier {
  package func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool {
    // The modifier is forwarded here. Content is either prepared under an
    // explicitly certified same-node primitive context, or updated by the
    // actual structural/composed carrier. Outer reflection must never walk it
    // under a guessed node/path first.
    index == 0 || index == 1
  }

  package func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    var result = runForwardedDynamicPropertyUpdates(on: modifier, in: context)
    guard let primitive = modifier as? any PrimitiveViewModifier else {
      // A composed modifier may place Content anywhere in an arbitrary body,
      // so the outer wrapper cannot invent a preparation context. Deny outer
      // reuse; the ViewModifierContent carrier updates once at its real node.
      return hasDynamicPropertyUpdateSurface(content)
        ? result.merging(.uncertified)
        : result
    }

    let inputs = ModifierContentInputs(
      base: content,
      authoringScope: authoringScope
    )
    guard
      let contentContext = primitive.dynamicPropertyContentPreparation(
        content: inputs,
        in: context.resolveContext
      ),
      contentContext.identity == context.resolveContext.identity,
      contentContext.structuralPath == context.resolveContext.structuralPath
    else {
      // Unknown and structural primitives are fail-closed. Their actual
      // content edge enters resolveView with the exact child/routed context.
      return hasDynamicPropertyUpdateSurface(content)
        ? result.merging(.uncertified)
        : result
    }
    result = result.merging(inputs.prepareDynamicProperties(in: contentContext))
    return result
  }

  package func hasAdditionalDynamicPropertyUpdateSurface() -> Bool {
    hasDynamicPropertyUpdateSurface(content)
      || hasDynamicPropertyUpdateSurface(modifier)
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
    let inputs = ModifierContentInputs(
      base: content,
      authoringScope: authoringScope
    )
    return withDynamicPropertyUpdateScope(modifier, for: context) {
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
