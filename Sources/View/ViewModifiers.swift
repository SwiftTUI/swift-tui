public import Core

extension View {
  public var body: Never {
    fatalError("\(Self.self) is a primitive view and does not expose a composed body.")
  }

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
    AnyView(resolving: IDView(identity: identity, content: self))
  }

  public func layoutMetadata(_ metadata: LayoutMetadata) -> some View {
    AnyView(resolving: LayoutMetadataModifier(content: self, metadata: metadata))
  }

  public func layoutValue<Key: LayoutValueKey>(
    key: Key.Type,
    value: Key.Value
  ) -> some View {
    LayoutValueModifier<Key, Self>(content: self, value: value)
  }

  public func alignmentGuide(
    _ alignment: HorizontalAlignment,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> some View {
    HorizontalAlignmentGuideModifier(
      content: self,
      alignment: alignment,
      computeValue: computeValue
    )
  }

  public func alignmentGuide(
    _ alignment: VerticalAlignment,
    computeValue: @escaping @Sendable (ViewDimensions) -> Int
  ) -> some View {
    VerticalAlignmentGuideModifier(
      content: self,
      alignment: alignment,
      computeValue: computeValue
    )
  }

  public func drawMetadata(_ metadata: DrawMetadata) -> some View {
    AnyView(resolving: DrawMetadataModifier(content: self, metadata: metadata))
  }

  public func semanticMetadata(_ metadata: SemanticMetadata) -> some View {
    AnyView(resolving: SemanticMetadataModifier(content: self, metadata: metadata))
  }

  public func onAppear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    AppearLifecycleModifier(content: self, action: action)
  }

  public func onDisappear(
    perform action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    DisappearLifecycleModifier(content: self, action: action)
  }

  public func task(
    priority: TaskPriority = .medium,
    @_inheritActorContext
    _ action: @escaping @isolated(any) @Sendable () async -> Void
  ) -> some View {
    TaskLifecycleModifier(
      content: self,
      priority: priority,
      descriptorID: nil,
      action: action
    )
  }

  public func task<ID: Hashable & Sendable>(
    id value: ID,
    priority: TaskPriority = .medium,
    @_inheritActorContext
    _ action: @escaping @isolated(any) @Sendable () async -> Void
  ) -> some View {
    TaskLifecycleModifier(
      content: self,
      priority: priority,
      descriptorID: String(reflecting: value),
      action: action
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
    PaddingView(content: erasedToAnyView, insets: .init(all: amount))
  }

  public func padding(_ insets: EdgeInsets) -> some View {
    PaddingView(content: erasedToAnyView, insets: insets)
  }

  public func frame(
    width: Int? = nil,
    height: Int? = nil,
    alignment: Alignment = .center
  ) -> some View {
    FrameView(
      content: erasedToAnyView,
      width: width,
      height: height,
      alignment: alignment
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
    FlexibleFrameView(
      content: erasedToAnyView,
      minWidth: minWidth,
      idealWidth: idealWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      idealHeight: idealHeight,
      maxHeight: maxHeight,
      alignment: alignment
    )
  }

  public func overlay<Content: View>(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) -> some View {
    OverlayView(
      base: self,
      overlay: content(),
      alignment: alignment
    )
  }

  public func background<Content: View>(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) -> some View {
    BackgroundView(
      base: self,
      background: content(),
      alignment: alignment
    )
  }

  public func environment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    _ value: Value
  ) -> some View {
    AnyView(
      resolving: EnvironmentWritingModifier(
        content: self,
        keyPath: keyPath,
        value: value
      )
    )
  }

  public func transformEnvironment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: @escaping (inout Value) -> Void
  ) -> some View {
    AnyView(
      resolving: EnvironmentTransformModifier(
        content: self,
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
  presentationRole: PresentationRole? = nil
) -> SemanticMetadata {
  .init(
    isFocusable: isFocusable,
    focusInteractions: focusInteractions,
    participatesInPointerHitTesting: true,
    scrollRole: scrollRole,
    presentationRole: presentationRole
  )
}

package func scrollViewMetadata(
  presentationRole: PresentationRole
) -> SemanticMetadata {
  .init(
    focusInteractions: .edit,
    participatesInPointerHitTesting: true,
    scrollRole: .scrollView,
    presentationRole: presentationRole
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

package struct IDView<Content: View>: View, ResolvableView {
  package var identity: Identity
  package var content: Content

  package init(identity: Identity, content: Content) {
    self.identity = identity
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [content.resolve(in: context.replacingIdentity(with: identity))]
  }
}

package struct LayoutMetadataModifier<Content: View>: View, ResolvableView {
  package var content: Content
  package var metadata: LayoutMetadata

  package init(content: Content, metadata: LayoutMetadata) {
    self.content = content
    self.metadata = metadata
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.layoutMetadata = node.layoutMetadata.merging(metadata)
    return [node]
  }
}

package struct DrawMetadataModifier<Content: View>: View, ResolvableView {
  package var content: Content
  package var metadata: DrawMetadata

  package init(content: Content, metadata: DrawMetadata) {
    self.content = content
    self.metadata = metadata
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.drawMetadata = node.drawMetadata.merging(metadata)
    return [node]
  }
}

package struct SemanticMetadataModifier<Content: View>: View, ResolvableView {
  package var content: Content
  package var metadata: SemanticMetadata

  package init(content: Content, metadata: SemanticMetadata) {
    self.content = content
    self.metadata = metadata
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.semanticMetadata = node.semanticMetadata.merging(metadata)
    return [node]
  }
}

private func lifecycleHandlerID(
  for identity: Identity,
  phase: String,
  ordinal: Int
) -> String {
  "\(identity)#\(phase)[\(ordinal)]"
}

private struct AppearLifecycleModifier<Content: View>: View, ResolvableView {
  var content: Content
  let action: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentDynamicPropertyScope()
    let lifecycleAction = action
    let handlerID = lifecycleHandlerID(
      for: node.identity,
      phase: "appear",
      ordinal: node.lifecycleMetadata.appearHandlerIDs.count
    )
    context.localLifecycleRegistry?.registerAppear(
      handlerID: handlerID,
      handler: {
        withDynamicPropertyScope(dynamicPropertyScope) {
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

private struct DisappearLifecycleModifier<Content: View>: View, ResolvableView {
  var content: Content
  let action: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentDynamicPropertyScope()
    let lifecycleAction = action
    let handlerID = lifecycleHandlerID(
      for: node.identity,
      phase: "disappear",
      ordinal: node.lifecycleMetadata.disappearHandlerIDs.count
    )
    context.localLifecycleRegistry?.registerDisappear(
      handlerID: handlerID,
      handler: {
        withDynamicPropertyScope(dynamicPropertyScope) {
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

private struct TaskLifecycleModifier<Content: View>: View, ResolvableView {
  var content: Content
  var priority: TaskPriority
  var descriptorID: String?
  let action: @Sendable () async -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentDynamicPropertyScope()
    let taskAction = action
    let descriptor = TaskDescriptor(
      id: descriptorID.map { "\(node.identity)#task[\($0)]" } ?? "\(node.identity)#task",
      priority: priority
    )
    if let taskRegistry = context.localTaskRegistry {
      taskRegistry.register(
        identity: node.identity,
        registration: .init(
          descriptor: descriptor,
          operation: {
            await withDynamicPropertyScope(dynamicPropertyScope) {
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

package struct EnvironmentWritingModifier<Content: View, Value>: View, ResolvableView {
  package var content: Content
  package var keyPath: WritableKeyPath<EnvironmentValues, Value>
  package var value: Value

  package init(
    content: Content,
    keyPath: WritableKeyPath<EnvironmentValues, Value>,
    value: Value
  ) {
    self.content = content
    self.keyPath = keyPath
    self.value = value
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    return content.resolveElements(in: context.settingEnvironment(keyPath, to: value))
  }
}

package struct EnvironmentTransformModifier<Content: View, Value>: View, ResolvableView {
  package var content: Content
  package var keyPath: WritableKeyPath<EnvironmentValues, Value>
  package var transform: (inout Value) -> Void

  package init(
    content: Content,
    keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: @escaping (inout Value) -> Void
  ) {
    self.content = content
    self.keyPath = keyPath
    self.transform = transform
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    content.resolveElements(
      in: context.transformingEnvironment(
        keyPath,
        transform: transform
      )
    )
  }
}

package struct PaddingView<Content: View>: View, ResolvableView {
  package var content: Content
  package var insets: EdgeInsets

  package init(content: Content, insets: EdgeInsets) {
    self.content = content
    self.insets = insets
  }

  @inline(never)
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentNode = resolveWrapperContent(
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

package struct FrameView<Content: View>: View, ResolvableView {
  package var content: Content
  package var width: Int?
  package var height: Int?
  package var alignment: Alignment

  package init(
    content: Content,
    width: Int?,
    height: Int?,
    alignment: Alignment
  ) {
    self.content = content
    self.width = width
    self.height = height
    self.alignment = alignment
  }

  @inline(never)
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentNode = resolveWrapperContent(
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

package struct FlexibleFrameView<Content: View>: View, ResolvableView {
  package var content: Content
  package var minWidth: ProposedDimension?
  package var idealWidth: ProposedDimension?
  package var maxWidth: ProposedDimension?
  package var minHeight: ProposedDimension?
  package var idealHeight: ProposedDimension?
  package var maxHeight: ProposedDimension?
  package var alignment: Alignment

  package init(
    content: Content,
    minWidth: ProposedDimension?,
    idealWidth: ProposedDimension?,
    maxWidth: ProposedDimension?,
    minHeight: ProposedDimension?,
    idealHeight: ProposedDimension?,
    maxHeight: ProposedDimension?,
    alignment: Alignment
  ) {
    self.content = content
    self.minWidth = minWidth
    self.idealWidth = idealWidth
    self.maxWidth = maxWidth
    self.minHeight = minHeight
    self.idealHeight = idealHeight
    self.maxHeight = maxHeight
    self.alignment = alignment
  }

  @inline(never)
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentNode = resolveWrapperContent(
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

package struct OverlayView<Base: View, OverlayContent: View>: View, ResolvableView {
  package var base: Base
  package var overlay: OverlayContent
  package var alignment: Alignment

  package init(base: Base, overlay: OverlayContent, alignment: Alignment) {
    self.base = base
    self.overlay = overlay
    self.alignment = alignment
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseNode = resolveWrapperContent(
      base,
      in: context.child(component: .named("base"))
    )
    let overlayNode = resolveWrapperContent(
      overlay,
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
private func resolveWrapperContent<Content: View>(
  _ content: Content,
  in context: ResolveContext
) -> ResolvedNode {
  let resolvedElements = content.resolveElements(in: context)

  switch resolvedElements.count {
  case 0:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("EmptyView"),
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      intrinsicSize: .zero
    )
  case 1:
    return resolvedElements[0]
  default:
    return ResolvedNode(
      identity: context.identity,
      kind: .view("Group"),
      children: resolvedElements,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
  }
}

package struct BackgroundView<Base: View, BackgroundContent: View>: View, ResolvableView {
  package var base: Base
  package var background: BackgroundContent
  package var alignment: Alignment

  package init(base: Base, background: BackgroundContent, alignment: Alignment) {
    self.base = base
    self.background = background
    self.alignment = alignment
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let backgroundNode = resolveWrapperContent(
      background,
      in: context.child(component: .named("background"))
    )
    let baseNode = resolveWrapperContent(
      base,
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
