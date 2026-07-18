package import SwiftTUICore

// The layout modifier implementation types.
//
// Each `*Modifier` here is the `PrimitiveViewModifier` value that one of the
// fluent `View` layout methods in `ViewLayoutModifiers.swift` constructs. Their
// `resolve` methods translate a stored configuration into a `ResolvedNode`
// carrying the matching `LayoutBehavior`, which the layout engine then honors.
//
// Split out of `ViewLayoutModifiers.swift` so that file stays a focused
// catalogue of the public `extension View` modifier API. The two private
// resolution helpers travel with the structs that call them, keeping their
// file-scoped `private` access intact.

public struct PaddingModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct SafeAreaPaddingModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct IgnoreSafeAreaModifier: PrimitiveViewModifier, Sendable, Equatable {
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
        layoutBehavior: .safeAreaIgnoring(reclaimedInsets, fillsProposal: false)
      )
    ]
  }
}

public struct SafeAreaInsetModifier<Inset: View>: PrimitiveViewModifier {
  package var inset: Inset
  package var edge: Edge
  package var alignment: Alignment
  package var spacing: Int
  package var insetAuthoringScope: CapturedSubviewScope

  package init(
    inset: Inset,
    edge: Edge,
    alignment: Alignment,
    spacing: Int,
    insetAuthoringScope: CapturedSubviewScope
  ) {
    self.inset = inset
    self.edge = edge
    self.alignment = alignment
    self.spacing = spacing
    self.insetAuthoringScope = insetAuthoringScope
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
      authoringScope: insetAuthoringScope,
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
public struct BorderModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct FrameModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct OffsetModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct PositionModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct MatchedGeometryModifier: PrimitiveViewModifier, Sendable, Equatable {
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

public struct FlexibleFrameModifier: PrimitiveViewModifier, Sendable, Equatable {
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
  package var overlayAuthoringScope: CapturedSubviewScope

  package init(
    overlay: OverlayContent,
    alignment: Alignment,
    overlayAuthoringScope: CapturedSubviewScope
  ) {
    self.overlay = overlay
    self.alignment = alignment
    self.overlayAuthoringScope = overlayAuthoringScope
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
      authoringScope: overlayAuthoringScope,
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
  authoringScope: CapturedSubviewScope,
  in context: ResolveContext
) -> ResolvedNode {
  withAuthoringContext(authoringScope.authoringContext) {
    resolveView(content, in: context)
  }
}

public struct BackgroundModifier<BackgroundContent: View>: PrimitiveViewModifier {
  package var background: BackgroundContent
  package var alignment: Alignment
  package var backgroundAuthoringScope: CapturedSubviewScope

  package init(
    background: BackgroundContent,
    alignment: Alignment,
    backgroundAuthoringScope: CapturedSubviewScope
  ) {
    self.background = background
    self.alignment = alignment
    self.backgroundAuthoringScope = backgroundAuthoringScope
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let backgroundNode = resolveStoredModifierView(
      background,
      authoringScope: backgroundAuthoringScope,
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
