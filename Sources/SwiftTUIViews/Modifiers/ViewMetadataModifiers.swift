public import SwiftTUICore

extension View {
  public func id<ID: Hashable & Sendable>(_ id: ID) -> some View {
    modifier(IDModifier(id: id))
  }

  package func id(_ identity: Identity) -> some View {
    modifier(ExactIdentityModifier(identity: identity))
  }

  package func layoutMetadata(_ metadata: LayoutMetadata) -> some View {
    modifier(LayoutMetadataModifier(metadata: metadata))
  }

  public func layoutValue<Key: LayoutValueKey>(
    key: Key.Type,
    value: Key.Value
  ) -> some View {
    modifier(LayoutValueModifier<Key>(value: value))
  }

  public func alignmentGuide(
    _ alignment: HorizontalAlignment,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> some View {
    modifier(
      HorizontalAlignmentGuideModifier(
        alignment: alignment,
        computeValue: computeValue
      )
    )
  }

  public func alignmentGuide(
    _ alignment: VerticalAlignment,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> some View {
    modifier(
      VerticalAlignmentGuideModifier(
        alignment: alignment,
        computeValue: computeValue
      )
    )
  }

  package func drawMetadata(_ metadata: DrawMetadata) -> some View {
    modifier(DrawMetadataModifier(metadata: metadata))
  }

  public func opacity(_ opacity: Double) -> some View {
    self.drawMetadata(.init(opacity: opacity))
  }

  public func semanticMetadata(_ metadata: SemanticMetadata) -> some View {
    modifier(SemanticMetadataModifier(metadata: metadata))
  }

  public func accessibilityRole(_ role: AccessibilityRole) -> some View {
    semanticMetadata(.init(accessibilityRole: role))
  }

  public func accessibilityLabel(_ label: String) -> some View {
    semanticMetadata(.init(accessibilityLabel: label))
  }

  public func accessibilityHint(_ hint: String) -> some View {
    semanticMetadata(.init(accessibilityHint: hint))
  }

  public func accessibilityHidden(_ hidden: Bool = true) -> some View {
    semanticMetadata(.init(accessibilityHidden: hidden))
  }

  public func accessibilityLiveRegion(
    _ politeness: AccessibilityPoliteness
  ) -> some View {
    semanticMetadata(.init(accessibilityLiveRegion: politeness))
  }

  /// Sets the local cell used by cursor-following accessibility mode.
  ///
  /// The anchor is relative to this view's semantic bounds. It does not change
  /// focus traversal or hit testing; the terminal runtime uses it only when
  /// cursor-following is enabled.
  public func accessibilityCursorAnchor(_ anchor: CellPoint) -> some View {
    semanticMetadata(.init(accessibilityCursorAnchor: anchor))
  }

  public func focusable(
    _ isFocusable: Bool = true,
    interactions: FocusInteractions = .automatic
  ) -> some View {
    semanticMetadata(
      .init(
        isFocusable: isFocusable,
        focusInteractions: interactions,
        participatesInPointerHitTesting: true
      )
    )
  }

  public func allowsHitTesting(_ allowed: Bool) -> some View {
    semanticMetadata(.init(allowsHitTesting: allowed))
  }

  public func focusEffectDisabled(
    _ disabled: Bool = true
  ) -> some View {
    environment(\.isFocusEffectEnabled, !disabled)
  }

  public func focusScope() -> some View {
    semanticMetadata(
      focusStructureMetadata(scopeBoundary: true)
    )
  }

  public func focusSection() -> some View {
    semanticMetadata(
      focusStructureMetadata(sectionBoundary: true)
    )
  }

  public func environment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    _ value: Value
  ) -> some View {
    modifier(
      EnvironmentWritingModifier(
        keyPath: keyPath,
        value: value
      )
    )
  }

  public func transformEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: @escaping (inout Value) -> Void
  ) -> some View {
    modifier(
      EnvironmentTransformModifier(
        keyPath: keyPath,
        transform: transform
      )
    )
  }
}

package func focusableControlMetadata(
  isFocusable: Bool? = nil,
  focusInteractions: FocusInteractions = .automatic,
  scrollRole: ScrollRole? = nil,
  accessibilityRole: AccessibilityRole? = nil
) -> SemanticMetadata {
  .init(
    isFocusable: isFocusable,
    focusInteractions: focusInteractions,
    participatesInPointerHitTesting: true,
    scrollRole: scrollRole,
    accessibilityRole: accessibilityRole
  )
}

package func scrollViewMetadata(
  accessibilityRole: AccessibilityRole
) -> SemanticMetadata {
  .init(
    isFocusable: true,
    focusInteractions: .edit,
    participatesInPointerHitTesting: true,
    // Capture the pointer on press so a drag that begins on scroll content
    // routes its whole `.dragged`/`.up` stream to the scroll view for
    // direct-manipulation panning. The body handler only claims the `.down`
    // while the content overflows, so non-scrollable presses still bubble.
    captureOnPress: true,
    scrollRole: .scrollView,
    accessibilityRole: accessibilityRole
  )
}

package func focusStructureMetadata(
  scopeBoundary: Bool = false,
  sectionBoundary: Bool = false
) -> SemanticMetadata {
  .init(
    focusScopeBoundary: scopeBoundary,
    focusSectionBoundary: sectionBoundary
  )
}

public struct IDModifier<ID: Hashable & Sendable>: PrimitiveViewModifier, Sendable, Equatable {
  package var id: ID

  package init(id: ID) {
    self.id = id
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let explicitIdentity = context.identity.explicitID(id)
    let entityIdentity = EntityIdentity(id)
    let routedContext = context.replacingIdentity(with: explicitIdentity)
    let route = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath
    )
    context.viewGraph?.prepareEntityRoutedOwner(
      entityIdentity,
      for: ViewNodeContext.current
    )
    var resolved = withResolveEntityRoute(route) {
      content.resolveOwned(in: routedContext)
    }
    resolved.attachingEntityIdentity(
      entityIdentity,
      at: context.structuralPath
    )
    return [resolved]
  }
}

extension IDModifier: EntityRouteProvidingModifier {
  package func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity {
    EntityIdentity(id)
  }
}

package struct ExactIdentityModifier: PrimitiveViewModifier, Sendable, Equatable {
  package var identity: Identity

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let entityIdentity = EntityIdentity(identity)
    var routedContext = context.replacingIdentity(with: identity)
    let slotNode = ViewNodeContext.current
    // Identity churn: the structural slot at this position resolved to a
    // *different* explicit identity last frame (e.g. `.id("owner-\(gen)")` with a
    // bumped generation). The committed reuse-containment checks key on
    // identity/structural ancestry, but this modifier (and `AnyView`,
    // captured-subview scopes below it) re-roots that ancestry, so a stable-`.id`
    // descendant escapes the owner's invalidation and is served its stale
    // first-generation snapshot. Mark the subtree so reuse is suppressed and
    // every positional descendant re-resolves with the fresh view value; the flag
    // rides `child` / `replacingIdentity` derivations, surviving each re-rooting
    // layer. Node `@State` slots persist across the recompute (they are keyed by
    // the descendant's own stable identity), so only closures/bindings/labels are
    // refreshed — not runtime state the framework deliberately keeps.
    //
    // Two churn shapes reach here since the modifier attaches an entity:
    // - Slot-node rebinding (`wasPresentAtFrameStart`, resolved identity
    //   moved): the slot node survived and re-rooted; suppress reuse for the
    //   arriving subtree so every positional descendant re-resolves fresh.
    //   Teardown of the departed generation is event-driven (displacement
    //   eviction, structural diff, hosted-detached edges) — no sweep.
    // - Displacement mint (`hasEntityDisplacedOccupantThisFrame`): the entity
    //   claim evicted a different-entity occupant and minted this node fresh,
    //   so the rebinding predicate can never fire; `nodeForIdentity` already
    //   tore the occupant down at the claim.
    if !routedContext.withinChurnedSubtree, let slotNode {
      // Continuity guard: when this modifier's entity already routes to the
      // slot node, the slot is this chain's steady home — the resolved
      // identity re-rooted because a *deeper* `.id` re-rooted it (a stable
      // `.id(control)` collapsed inside `.id(owner)`), not because a different
      // identity moved into this slot. A deeper churn fires its own predicate
      // at its own level; re-firing here would suppress reuse on every frame
      // of the steady state.
      let rebindChurn =
        slotNode.wasPresentAtFrameStart
        && slotNode.resolvedIdentity != slotNode.identity
        && !identity.isAncestor(of: slotNode.resolvedIdentity)
        && context.viewGraph?.entityRouteIsBound(entityIdentity, to: slotNode) != true
      if rebindChurn || slotNode.hasEntityDisplacedOccupantThisFrame {
        routedContext.withinChurnedSubtree = true
      }
    }
    let route = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath,
      escapesHostingBoundary: true
    )
    // Co-resident escape: an enclosing identity modifier already claimed this
    // slot node for a DIFFERENT entity (`.id(stable)` collapsing inside
    // `.id("owner-\(gen)")` with no builder boundary between them). Fusing
    // both entities onto the one slot node makes the one-entity-per-node
    // routing claims fight, the foreign occupant check in
    // `prepareEntityRoutedOwner` wipes the stable chain's state slots on
    // every re-resolve, and the owner churn's occupant eviction destroys the
    // stable entity's home (structural task cancel + state reset). Give the
    // re-rooted chain its own node boundary instead: resolve the content
    // through `resolveView` at the explicit identity — the interior node owns
    // the state slots, the task label slots, and the entity route — and
    // present it as a real CHILD of a host shell keyed by the enclosing
    // identity. The child keeps the entity in the committed tree (so the
    // route survives the barrier's inactive-entity release), the shell keeps
    // the slot node's resolved identity in the enclosing entity's namespace
    // (so its reindex never steals the interior's identity index entry), and
    // an owner churn's occupant eviction reaches the interior as an
    // entity-routed child — deferred to the frame barrier, where the arriving
    // generation's re-adoption keeps it alive.
    if !context.entityHosting,
      let slotNode,
      let occupant = context.viewGraph?.entityOccupant(of: slotNode),
      occupant != entityIdentity
    {
      let hosted = withResolveEntityRoute(route) {
        resolveView(
          EntityRootedChainContent(
            content: content,
            entityIdentity: entityIdentity,
            entityStructuralPath: context.structuralPath
          ),
          in: routedContext
        )
      }
      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("ExplicitIdentityHost"),
          children: [hosted],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction
        )
      ]
    }
    // Mirror `IDModifier`: attach the entity so the churn is visible to
    // `ChildDescriptor` diffing and the entity routing table, and pre-bind the
    // slot node as the entity's owner so interior same-path resolution routes
    // to it (the transparent-chain collapse). Suppressed while a
    // non-transparent host resolves this chain through its own node
    // (`entityHosting`): the host must stay a positional node, never the
    // entity's home — the route also escapes the host's identity subtree
    // (`escapesHostingBoundary`), so hosting boundaries refuse to claim it.
    if !context.entityHosting {
      context.viewGraph?.prepareEntityRoutedOwner(
        entityIdentity,
        for: slotNode
      )
    }
    var resolved = withResolveEntityRoute(route) {
      content.resolveOwned(in: routedContext)
    }
    resolved.attachingEntityIdentity(
      entityIdentity,
      at: context.structuralPath
    )
    return [resolved]
  }
}

/// The content of a co-resident `ExactIdentityModifier` chain resolved through
/// its own node boundary (see the escape branch in
/// `ExactIdentityModifier.resolve`). The entity attaches BEFORE the enclosing
/// `resolveView` applies the value, so the interior node's committed value
/// carries it — that stamp is what defers the node's removal to the frame
/// barrier when an enclosing owner churn evicts its absorber.
private struct EntityRootedChainContent<Base: View>: PrimitiveView, ResolvableView {
  let content: ModifierContentInputs<Base>
  let entityIdentity: EntityIdentity
  let entityStructuralPath: StructuralPath

  var body: Never {
    fatalError("EntityRootedChainContent is resolved directly.")
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolved = content.resolveOwned(in: context)
    resolved.attachingEntityIdentity(
      entityIdentity,
      at: entityStructuralPath
    )
    return [resolved]
  }
}

extension ExactIdentityModifier: EntityRouteProvidingModifier {
  package func resolveEntityRouteIdentity(in context: ResolveContext) -> EntityIdentity {
    EntityIdentity(identity)
  }

  package var providesHostEscapingEntityRoute: Bool { true }
}

package struct LayoutMetadataModifier: PrimitiveViewModifier, Sendable {
  package var metadata: LayoutMetadata

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.merging(metadata)
    return [node]
  }
}

public struct LayoutValueModifier<Key: LayoutValueKey>: PrimitiveViewModifier {
  var value: Key.Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingLayoutValue(
      value,
      for: ObjectIdentifier(Key.self),
      debugName: String(reflecting: Key.self),
      debugValue: String(describing: value)
    )
    return [node]
  }
}

public struct HorizontalAlignmentGuideModifier: PrimitiveViewModifier, Sendable {
  var alignment: HorizontalAlignment
  var computeValue: @Sendable (ViewDimensions) -> Int

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingHorizontalAlignmentGuide(
      alignment,
      debugName: alignment.debugName,
      computeValue: computeValue
    )
    return [node]
  }
}

public struct VerticalAlignmentGuideModifier: PrimitiveViewModifier, Sendable {
  var alignment: VerticalAlignment
  var computeValue: @Sendable (ViewDimensions) -> Int

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.settingVerticalAlignmentGuide(
      alignment,
      debugName: alignment.debugName,
      computeValue: computeValue
    )
    return [node]
  }
}

public struct DrawMetadataModifier: PrimitiveViewModifier, Sendable, Equatable {
  package var metadata: DrawMetadata

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.drawMetadata = node.drawMetadata.merging(metadata)
    return [node]
  }
}

package struct DrawEffectModifier: PrimitiveViewModifier, Sendable, Equatable {
  package var effect: DrawEffect

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.drawEffects.append(effect)
    if effect == .compositingGroup {
      node.surfaceComposition = .init(
        role: .isolatedCompositingGroup,
        stableKey: node.identity.path,
        invalidationScope: .compositedBounds
      )
    }
    return [node]
  }
}

extension DrawMetadataModifier: TransitionEffectProvidingModifier {
  package func contributeTransitionEffects(into modifiers: inout TransitionModifiers) {
    if let opacity = metadata.baseStyle.explicitOpacity {
      modifiers.opacity = opacity
    }
  }
}

public struct SemanticMetadataModifier: PrimitiveViewModifier, Sendable, Equatable {
  package var metadata: SemanticMetadata

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.semanticMetadata = node.semanticMetadata.merging(metadata)
    return [node]
  }
}

extension SemanticMetadataModifier: TabItemMetadataProvidingModifier {
  package var tabItemMetadataContribution: PeekedTabChildMetadata {
    PeekedTabChildMetadata(
      label: metadata.tabItemLabel,
      tag: metadata.selectionTag
    )
  }
}

public struct EnvironmentWritingModifier<Value>: PrimitiveViewModifier {
  package var keyPath: WritableKeyPath<EnvironmentValues, Value>
  package var value: Value

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return content.resolveElements(in: context.settingEnvironment(keyPath, to: value))
  }
}

public struct EnvironmentTransformModifier<Value>: PrimitiveViewModifier {
  package var keyPath: WritableKeyPath<EnvironmentValues, Value>
  package var transform: (inout Value) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    content.resolveElements(
      in: context.transformingEnvironment(keyPath) { value in
        content.withAuthoredClosureScope {
          transform(&value)
        }
      }
    )
  }
}
