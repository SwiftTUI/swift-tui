public import SwiftTUICore

extension View {
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
  /// geometry as the "from" reference; the non-source instances
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
