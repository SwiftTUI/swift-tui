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
  /// focus traversal or hit testing. The terminal runtime uses it only when
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

/// Semantics for a scroll view container.
///
/// `capturesPointerOnPress` mirrors the host's
/// ``PointerInputCapabilities/supportsScrollPanning`` declaration. When it is
/// on, the pointer is captured on press so a drag that begins on scroll
/// content routes its whole `.dragged`/`.up` stream to the scroll view for
/// direct-manipulation panning (the body handler still only claims the
/// `.down` while content overflows, so non-scrollable presses bubble). When
/// the host does not pan by dragging, the body must not capture at all — a
/// captured press over scroll content would swallow the interaction stream
/// nothing is going to use.
package func scrollViewMetadata(
  accessibilityRole: AccessibilityRole,
  capturesPointerOnPress: Bool
) -> SemanticMetadata {
  .init(
    isFocusable: true,
    focusInteractions: .edit,
    participatesInPointerHitTesting: true,
    captureOnPress: capturesPointerOnPress,
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

@MainActor
private func exactEntityIdentity(
  _ identity: Identity,
  occurrence: Int = 0,
  in context: ResolveContext
) -> EntityIdentity {
  let scope =
    ResolveEntityRouteStorage.current?.identity
    ?? EntityIdentity(context.structuralPath.identityProjection)
  return EntityIdentity(
    exactIdentity: identity,
    occurrence: occurrence,
    scope: scope
  )
}

package struct ExactIdentityModifier: PrimitiveViewModifier, Sendable, Equatable {
  package var identity: Identity

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let slotNode = ViewNodeContext.current
    // Duplicate `.id(exact)` siblings under one body are distinct runtime
    // lifetimes. Claim this chain's occurrence before the entity claim so the
    // second sibling routes to its own home instead of thrashing the primary's.
    let occurrence =
      slotNode?.claimExactIdentityOccurrence(
        for: identity,
        at: context.structuralPath
      ) ?? 0
    let entityIdentity = exactEntityIdentity(
      identity,
      occurrence: occurrence,
      in: context
    )
    let routedContext = context.replacingIdentity(with: identity)
    let route = ResolveEntityRoute(
      identity: entityIdentity,
      structuralPath: context.structuralPath,
      escapesHostingBoundary: true
    )
    // Nested exact IDs need separate nodes so both identity boundaries exist
    // in the graph. The inner entity is scoped to the enclosing entity above,
    // so this node survives moves within that ancestor lifetime but is removed
    // when the ancestor ID changes.
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
    exactEntityIdentity(identity, in: context)
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
