public import SwiftTUICore

extension View {
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveViewElements(self, in: context)
  }

  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }

  /// Erases `self` for local branch unification or interoperability.
  ///
  /// Prefer typed `@ViewBuilder` composition and generic storage when possible.
  /// If authored content will be stored for later evaluation, prefer
  /// `scopedAnyView(...)` over storing this result directly.
  public var erasedToAnyView: AnyView {
    AnyView(self)
  }

  public func id(_ identity: Identity) -> some View {
    modifier(IDModifier(identity: identity))
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

  public func onAppear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(AppearLifecycleModifier(action: action))
  }

  public func onDisappear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    modifier(DisappearLifecycleModifier(action: action))
  }

  public func onChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping () -> Void
  ) -> some View {
    modifier(
      ChangeLifecycleModifier(
        value: value,
        initial: initial,
        action: { _, _ in action() }
      )
    )
  }

  public func onChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping (Value, Value) -> Void
  ) -> some View {
    modifier(
      ChangeLifecycleModifier(
        value: value,
        initial: initial,
        action: action
      )
    )
  }

  public func task(
    priority: TaskPriority = .userInitiated,
    @_inheritActorContext
    _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(
      TaskLifecycleModifier(
        priority: priority,
        descriptorIdentity: nil,
        action: action
      )
    )
  }

  public func task<ID: Equatable>(
    id value: ID,
    priority: TaskPriority = .userInitiated,
    @_inheritActorContext
    _ action: sending @escaping @isolated(any) () async -> Void
  ) -> some View {
    modifier(
      TaskLifecycleModifier(
        priority: priority,
        descriptorIdentity: TaskLifecycleDescriptorIdentity(value),
        action: action
      )
    )
  }

  public func layoutPriority(_ priority: Double) -> some View {
    layoutMetadata(.init(layoutPriority: priority))
  }

  public func fixedSize() -> some View {
    fixedSize(horizontal: true, vertical: true)
  }

  public func fixedSize(
    horizontal: Bool,
    vertical: Bool
  ) -> some View {
    layoutMetadata(
      .init(
        fixedSizeHorizontal: horizontal,
        fixedSizeVertical: vertical
      )
    )
  }

  public func lineLimit(_ limit: Int?) -> some View {
    layoutMetadata(.init(lineLimit: limit.map { max(1, $0) }))
  }

  public func truncationMode(_ mode: Text.TruncationMode) -> some View {
    layoutMetadata(.init(textTruncationMode: mode))
  }

  public func textWrappingStrategy(_ strategy: Text.WrappingStrategy) -> some View {
    layoutMetadata(.init(textWrappingStrategy: strategy))
  }

  public func clipped() -> some View {
    drawMetadata(.init(clipsToBounds: true))
  }

  public func offset(_ offset: CellSize) -> some View {
    modifier(
      OffsetModifier(
        x: offset.width,
        y: offset.height
      )
    )
  }

  public func offset(
    x: Int = 0,
    y: Int = 0
  ) -> some View {
    modifier(
      OffsetModifier(
        x: x,
        y: y
      )
    )
  }

  /// Positions the center of this view at `(x, y)` in its parent's
  /// coordinate space.
  ///
  /// Unlike ``offset(x:y:)``, which translates the view without
  /// affecting parent layout, `.position` wraps the view in a
  /// container that takes the full proposed space so the parent
  /// reserves room for the absolute placement area.  Matches
  /// SwiftUI's `View.position(x:y:)` semantics.
  public func position(
    x: Int = 0,
    y: Int = 0
  ) -> some View {
    modifier(
      PositionModifier(
        x: x,
        y: y
      )
    )
  }

  /// Tags this view with a matched-geometry key so the animation
  /// controller can recognize it across conditional re-creation
  /// (e.g. `if`/`else` branches that swap between two layouts)
  /// and animate the transition as if a single view moved from
  /// the old location to the new one.
  ///
  /// Matches SwiftUI's `.matchedGeometryEffect(id:in:isSource:)`
  /// API shape.  Scope keys with `@Namespace` or pass a
  /// ``MatchedGeometryNamespace`` value explicitly.
  ///
  /// `isSource: false` lets you have multiple views with the same
  /// key where only the designated source view contributes its
  /// geometry as the "from" reference — the non-source instances
  /// still receive the match and are positioned at the source's
  /// location when they appear.
  ///
  /// - Note: The current implementation interpolates position only,
  ///   not size.  A view that changes width between its source and
  ///   destination will appear at its natural destination size
  ///   throughout the animation and translate its origin smoothly.
  public func matchedGeometryEffect<ID: Hashable>(
    id: ID,
    in namespace: MatchedGeometryNamespace = .default,
    isSource: Bool = true
  ) -> some View {
    modifier(
      MatchedGeometryModifier(
        config: MatchedGeometryConfig(
          key: MatchedGeometryKey(namespace: namespace, id: id),
          isSource: isSource
        )
      )
    )
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

  public func padding(_ amount: Int = 1) -> some View {
    modifier(PaddingModifier(insets: .init(all: amount)))
  }

  public func padding(_ insets: EdgeInsets) -> some View {
    modifier(PaddingModifier(insets: insets))
  }

  public func padding(_ edges: Edge.Set, _ amount: Int = 1) -> some View {
    modifier(
      PaddingModifier(
        insets: EdgeInsets(
          top: edges.contains(.top) ? amount : 0,
          leading: edges.contains(.leading) ? amount : 0,
          bottom: edges.contains(.bottom) ? amount : 0,
          trailing: edges.contains(.trailing) ? amount : 0
        )
      )
    )
  }

  public func safeAreaPadding(
    _ edges: Edge.Set = .all
  ) -> some View {
    modifier(
      SafeAreaPaddingModifier(
        edges: edges,
        additional: 0
      )
    )
  }

  public func safeAreaPadding(
    _ amount: Int
  ) -> some View {
    safeAreaPadding(.all, amount)
  }

  public func safeAreaPadding(
    _ edges: Edge.Set,
    _ amount: Int
  ) -> some View {
    modifier(
      SafeAreaPaddingModifier(
        edges: edges,
        additional: amount
      )
    )
  }

  public func ignoresSafeArea(
    _ edges: Edge.Set = .all
  ) -> some View {
    modifier(IgnoreSafeAreaModifier(edges: edges))
  }

  public func safeAreaInset<Inset: View>(
    edge: Edge,
    alignment: Alignment = .center,
    spacing: Int = 0,
    @ViewBuilder content: () -> Inset
  ) -> some View {
    modifier(
      SafeAreaInsetModifier(
        inset: content(),
        edge: edge,
        alignment: alignment,
        spacing: spacing,
        insetAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func frame(
    width: Int? = nil,
    height: Int? = nil,
    alignment: Alignment = .center
  ) -> some View {
    modifier(
      FrameModifier(
        width: width,
        height: height,
        alignment: alignment
      )
    )
  }

  public func frame(
    minWidth: ProposedDimension? = nil,
    idealWidth: ProposedDimension? = nil,
    maxWidth: ProposedDimension? = nil,
    minHeight: ProposedDimension? = nil,
    idealHeight: ProposedDimension? = nil,
    maxHeight: ProposedDimension? = nil,
    alignment: Alignment = .center
  ) -> some View {
    modifier(
      FlexibleFrameModifier(
        minWidth: minWidth,
        idealWidth: idealWidth,
        maxWidth: maxWidth,
        minHeight: minHeight,
        idealHeight: idealHeight,
        maxHeight: maxHeight,
        alignment: alignment
      )
    )
  }

  public func overlay<Content: View>(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) -> some View {
    modifier(
      OverlayModifier(
        overlay: content(),
        alignment: alignment,
        overlayAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  public func background<Content: View>(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) -> some View {
    modifier(
      BackgroundModifier(
        background: content(),
        alignment: alignment,
        backgroundAuthoringContext: makeDeferredAuthoringContext()
      )
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

public struct IDModifier: PrimitiveViewModifier {
  package var identity: Identity

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [content.resolve(in: context.replacingIdentity(with: identity))]
  }
}

package struct LayoutMetadataModifier: PrimitiveViewModifier {
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

public struct DrawMetadataModifier: PrimitiveViewModifier {
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

extension DrawMetadataModifier: TransitionEffectProvidingModifier {
  package func contributeTransitionEffects(into modifiers: inout TransitionModifiers) {
    if let opacity = metadata.baseStyle.explicitOpacity {
      modifiers.opacity = opacity
    }
  }
}

public struct SemanticMetadataModifier: PrimitiveViewModifier {
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

private func lifecycleHandlerID(
  for identity: Identity,
  phase: String,
  ordinal: Int
) -> String {
  "\(identity)#\(phase)[\(ordinal)]"
}

@MainActor
private func recordLifecycleEvaluationOwner(
  for lifecycleIdentity: Identity,
  in context: ResolveContext
) {
  context.viewGraph?.recordLifecycleEvaluationOwner(
    target: lifecycleIdentity,
    owner: context.identity
  )
}

public struct AppearLifecycleModifier: PrimitiveViewModifier {
  let action: () -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let lifecycleAction = action
    let handlerID = lifecycleHandlerID(
      for: node.identity,
      phase: "appear",
      ordinal: node.lifecycleMetadata.appearHandlerIDs.count
    )
    context.localLifecycleRegistry?.registerAppear(
      handlerID: handlerID,
      handler: {
        withImperativeAuthoringContext(authoringContext) {
          lifecycleAction()
        }
      }
    )
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(appearHandlerIDs: [handlerID])
    )
    return [node]
  }
}

public struct DisappearLifecycleModifier: PrimitiveViewModifier {
  let action: () -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let lifecycleAction = action
    let handlerID = lifecycleHandlerID(
      for: node.identity,
      phase: "disappear",
      ordinal: node.lifecycleMetadata.disappearHandlerIDs.count
    )
    context.localLifecycleRegistry?.registerDisappear(
      handlerID: handlerID,
      handler: {
        withImperativeAuthoringContext(authoringContext) {
          lifecycleAction()
        }
      }
    )
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(disappearHandlerIDs: [handlerID])
    )
    return [node]
  }
}

public struct ChangeLifecycleModifier<Value: Equatable>: PrimitiveViewModifier {
  var value: Value
  var initial: Bool
  let action: (Value, Value) -> Void

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let node = content.resolve(in: context)
    let ownerNode = context.viewGraph?.nodeForIdentity(node.identity)
    let modifierOrdinal = ownerNode?.claimChangeModifierOrdinal() ?? 0
    let stateSlotOrdinal = StateSlotOrdinals.changeModifier(modifierOrdinal)
    let hadPreviousValue = ownerNode?.hasStateSlot(ordinal: stateSlotOrdinal) == true
    let previousValue = ownerNode.map { ownerNode in
      ownerNode.stateSlot(
        ordinal: stateSlotOrdinal,
        seed: value
      )
    }
    let shouldTrigger =
      if hadPreviousValue {
        previousValue.map { $0 != value } ?? false
      } else {
        initial
      }

    if let ownerNode {
      ownerNode.setStateSlotSilently(
        ordinal: stateSlotOrdinal,
        value: value
      )
    }

    guard shouldTrigger else {
      return [node]
    }

    let oldValue = previousValue ?? value
    let lifecycleAction = action
    let handlerID = lifecycleHandlerID(
      for: node.identity,
      phase: "change",
      ordinal: modifierOrdinal
    )

    context.localLifecycleRegistry?.registerChange(
      handlerID: handlerID,
      handler: {
        withImperativeAuthoringContext(authoringContext) {
          lifecycleAction(oldValue, value)
        }
      }
    )
    ownerNode?.queueChangeHandler(handlerID)
    return [node]
  }
}

private struct TaskLifecycleDescriptorIdentity {
  private let label: @MainActor (ResolveContext, Identity) -> String

  @MainActor
  init<ID: Equatable>(_ value: ID) {
    label = { context, identity in
      if let graphLabel = context.viewGraph?.taskDescriptorIdentityLabel(
        for: identity,
        value: value
      ) {
        return graphLabel
      }
      return "id:\(String(reflecting: ID.self))"
    }
  }

  @MainActor
  func descriptorLabel(
    in context: ResolveContext,
    identity: Identity
  ) -> String {
    label(context, identity)
  }
}

public struct TaskLifecycleModifier: PrimitiveViewModifier {
  var priority: TaskPriority
  fileprivate var descriptorIdentity: TaskLifecycleDescriptorIdentity?
  let action: () async -> Void

  fileprivate init(
    priority: TaskPriority,
    descriptorIdentity: TaskLifecycleDescriptorIdentity?,
    action: @escaping () async -> Void
  ) {
    self.priority = priority
    self.descriptorIdentity = descriptorIdentity
    self.action = action
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    let taskAction = action
    let lifecycleIdentity = node.identity
    recordLifecycleEvaluationOwner(
      for: lifecycleIdentity,
      in: context
    )
    let descriptorIdentityLabel = descriptorIdentity?.descriptorLabel(
      in: context,
      identity: lifecycleIdentity
    )
    let descriptor = TaskDescriptor(
      id: descriptorIdentityLabel.map {
        "\(lifecycleIdentity)#task[\($0)]"
      } ?? "\(lifecycleIdentity)#task",
      priority: priority
    )
    if let taskRegistry = context.localTaskRegistry {
      taskRegistry.register(
        identity: lifecycleIdentity,
        registration: .init(
          descriptor: descriptor,
          operation: {
            await withImperativeAuthoringContext(authoringContext) {
              await taskAction()
            }
          }
        )
      )
    }
    node.lifecycleMetadata = node.lifecycleMetadata.merging(
      .init(task: descriptor)
    )
    return [node]
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
      in: context.transformingEnvironment(
        keyPath,
        transform: transform
      )
    )
  }
}

public struct PaddingModifier: PrimitiveViewModifier {
  package var insets: EdgeInsets

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Padding"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .padding(insets)
      )
    ]
  }
}

public struct SafeAreaPaddingModifier: PrimitiveViewModifier {
  package var edges: Edge.Set
  package var additional: Int

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let safeAreaInsets = context.environmentValues.safeAreaInsets.masked(to: edges)
    let appliedInsets = safeAreaInsets.adding(
      max(0, additional),
      to: edges
    )
    let contentContext =
      context.child(component: .named("content"))
      .transformingEnvironment(\.safeAreaInsets) { safeAreaInsets in
        safeAreaInsets = safeAreaInsets.adding(appliedInsets)
      }
    let contentNode = resolveModifierContent(content, in: contentContext)
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("SafeAreaPadding"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .padding(appliedInsets)
      )
    ]
  }
}

public struct IgnoreSafeAreaModifier: PrimitiveViewModifier {
  package var edges: Edge.Set

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let reclaimedInsets = context.environmentValues.safeAreaInsets.masked(to: edges)
    let contentContext =
      context.child(component: .named("content"))
      .transformingEnvironment(\.safeAreaInsets) { safeAreaInsets in
        safeAreaInsets = safeAreaInsets.zeroing(edges)
      }
    let contentNode = resolveModifierContent(content, in: contentContext)
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("IgnoreSafeArea"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .safeAreaIgnoring(reclaimedInsets)
      )
    ]
  }
}

public struct SafeAreaInsetModifier<Inset: View>: PrimitiveViewModifier {
  package var inset: Inset
  package var edge: Edge
  package var alignment: Alignment
  package var spacing: Int
  package var insetAuthoringContext: AuthoringContext?

  package init(
    inset: Inset,
    edge: Edge,
    alignment: Alignment,
    spacing: Int,
    insetAuthoringContext: AuthoringContext?
  ) {
    self.inset = inset
    self.edge = edge
    self.alignment = alignment
    self.spacing = spacing
    self.insetAuthoringContext = insetAuthoringContext
  }

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let baseNode = resolveModifierContent(
      content,
      in: context.child(component: .named("base"))
    )
    let insetNode = resolveStoredModifierView(
      inset,
      authoringContext: insetAuthoringContext,
      in: context.child(component: .named("inset"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("SafeAreaInset"),
        children: [baseNode, insetNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .safeAreaInset(
          edge: edge,
          alignment: alignment,
          spacing: max(0, spacing),
          safeArea: context.environmentValues.safeAreaInsets
        )
      )
    ]
  }
}

/// Wrapper that installs a ``LayoutBehavior/border`` on its child so the
/// layout engine reserves frame space for the border glyphs and the
/// rasterizer paints them into the reserved cells.
public struct BorderModifier: PrimitiveViewModifier {
  package var set: BorderSet
  package var placement: StrokeStyle.Placement
  package var foreground: BorderEdgeStyle?
  package var background: BorderBackgroundStyle?
  package var blend: BorderBlend?
  package var blendPhase: Double
  package var sides: Edge.Set

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Border"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .border(
          set,
          placement: placement,
          foreground: foreground,
          background: background,
          blend: blend,
          blendPhase: blendPhase,
          sides: sides
        )
      )
    ]
  }

  private var layoutInsets: EdgeInsets {
    guard placement != .inset else {
      return .zero
    }

    return EdgeInsets(
      top: sides.contains(.top) ? set.topDisplayWidth : 0,
      leading: sides.contains(.leading) ? set.leftDisplayWidth : 0,
      bottom: sides.contains(.bottom) ? set.bottomDisplayWidth : 0,
      trailing: sides.contains(.trailing) ? set.rightDisplayWidth : 0
    )
  }
}

public struct FrameModifier: PrimitiveViewModifier {
  package var width: Int?
  package var height: Int?
  package var alignment: Alignment

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Frame"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .frame(width: width, height: height, alignment: alignment)
      )
    ]
  }
}

public struct OffsetModifier: PrimitiveViewModifier {
  package var x: Int
  package var y: Int

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Offset"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .offset(x: x, y: y)
      )
    ]
  }
}

extension OffsetModifier: TransitionEffectProvidingModifier {
  package func contributeTransitionEffects(into modifiers: inout TransitionModifiers) {
    modifiers.offsetX = x
    modifiers.offsetY = y
  }
}

public struct PositionModifier: PrimitiveViewModifier {
  package var x: Int
  package var y: Int

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Position"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .position(x: x, y: y)
      )
    ]
  }
}

public struct MatchedGeometryModifier: PrimitiveViewModifier {
  package var config: MatchedGeometryConfig

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let nodes = content.resolveElements(in: context)
    return nodes.map { node in
      var tagged = node
      tagged.matchedGeometry = config
      return tagged
    }
  }
}

public struct FlexibleFrameModifier: PrimitiveViewModifier {
  package var minWidth: ProposedDimension?
  package var idealWidth: ProposedDimension?
  package var maxWidth: ProposedDimension?
  package var minHeight: ProposedDimension?
  package var idealHeight: ProposedDimension?
  package var maxHeight: ProposedDimension?
  package var alignment: Alignment

  @inline(never)
  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let contentNode = resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("FlexibleFrame"),
        children: [contentNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .flexibleFrame(
          minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
          minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
          alignment: alignment
        )
      )
    ]
  }
}

public struct OverlayModifier<OverlayContent: View>: PrimitiveViewModifier {
  package var overlay: OverlayContent
  package var alignment: Alignment
  package var overlayAuthoringContext: AuthoringContext?

  package init(
    overlay: OverlayContent,
    alignment: Alignment,
    overlayAuthoringContext: AuthoringContext?
  ) {
    self.overlay = overlay
    self.alignment = alignment
    self.overlayAuthoringContext = overlayAuthoringContext
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let baseNode = resolveModifierContent(
      content,
      in: context.child(component: .named("base"))
    )
    let overlayNode = resolveStoredModifierView(
      overlay,
      authoringContext: overlayAuthoringContext,
      in: context.child(component: .named("overlay"))
    )
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

@inline(never)
@MainActor
private func resolveModifierContent<Base: View>(
  _ content: ModifierContentInputs<Base>,
  in context: ResolveContext
) -> ResolvedNode {
  content.resolve(in: context)
}

@inline(never)
@MainActor
private func resolveStoredModifierView<Content: View>(
  _ content: Content,
  authoringContext: AuthoringContext?,
  in context: ResolveContext
) -> ResolvedNode {
  withAuthoringContext(authoringContext) {
    resolveView(content, in: context)
  }
}

public struct BackgroundModifier<BackgroundContent: View>: PrimitiveViewModifier {
  package var background: BackgroundContent
  package var alignment: Alignment
  package var backgroundAuthoringContext: AuthoringContext?

  package init(
    background: BackgroundContent,
    alignment: Alignment,
    backgroundAuthoringContext: AuthoringContext?
  ) {
    self.background = background
    self.alignment = alignment
    self.backgroundAuthoringContext = backgroundAuthoringContext
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let backgroundNode = resolveStoredModifierView(
      background,
      authoringContext: backgroundAuthoringContext,
      in: context.child(component: .named("background"))
    )
    let baseNode = resolveModifierContent(
      content,
      in: context.child(component: .named("base"))
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
