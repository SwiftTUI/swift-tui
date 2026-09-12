import SwiftTUICore

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

public struct PaddingModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var insets: EdgeInsets

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct SafeAreaPaddingModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var edges: Edge.Set
  package var additional: Int

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
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
    return resolveModifierContent(content, in: contentContext).map { contentNode in
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
}

public struct IgnoreSafeAreaModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var edges: Edge.Set

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let reclaimedInsets = context.environmentValues.safeAreaInsets.masked(to: edges)
    let contentContext =
      context.child(component: .named("content"))
      .transformingEnvironment(\.safeAreaInsets) { safeAreaInsets in
        safeAreaInsets = safeAreaInsets.zeroing(edges)
      }
    return resolveModifierContent(content, in: contentContext).map { contentNode in
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
}

public struct SafeAreaInsetModifier<Inset: View>: IterativePrimitiveViewModifier {
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
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("base"))
    ).flatMap { baseNode in
      return resolveStoredModifierView(
        inset,
        authoringScope: insetAuthoringScope,
        in: context.child(component: .named("inset"))
      ).map { insetNode in
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
  }
}

/// A wrapper that installs a `LayoutBehavior.border` on its child.
/// The layout engine reserves frame space for the border glyphs.
/// The rasterizer paints the glyphs into the reserved cells.
public struct BorderModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var set: BorderSet
  package var placement: StrokeStyle.Placement
  package var foreground: BorderEdgeStyle?
  package var background: BorderBackgroundStyle?
  package var blend: BorderBlend?
  package var blendPhase: Double
  package var sides: Edge.Set

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct FrameModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var width: Int?
  package var height: Int?
  package var alignment: Alignment

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct OffsetModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var x: Int
  package var y: Int

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct PositionModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var x: Int
  package var y: Int

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct MatchedGeometryModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var config: MatchedGeometryConfig

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return content.resolveElementsWork(in: context).map { nodes in
      return nodes.map { node in
        var tagged = node
        tagged.matchedGeometry = config
        return tagged
      }

    }
  }
}

public struct FlexibleFrameModifier: IterativePrimitiveViewModifier, Sendable, Equatable {
  package var minWidth: ProposedDimension?
  package var idealWidth: ProposedDimension?
  package var maxWidth: ProposedDimension?
  package var minHeight: ProposedDimension?
  package var idealHeight: ProposedDimension?
  package var maxHeight: ProposedDimension?
  package var alignment: Alignment

  @inline(never)
  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("content"))
    ).map { contentNode in
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
}

public struct OverlayModifier<OverlayContent: View>: IterativePrimitiveViewModifier {
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

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveModifierContent(
      content,
      in: context.child(component: .named("base"))
    ).flatMap { baseNode in
      return resolveStoredModifierView(
        overlay,
        authoringScope: overlayAuthoringScope,
        in: context.child(component: .named("overlay"))
      ).map { overlayNode in
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
  }
}

@inline(never)
@MainActor
private func resolveModifierContent<Base: View>(
  _ content: ModifierContentInputs<Base>,
  in context: ResolveContext
) -> ResolveWork<ResolvedNode> {
  content.resolveWork(in: context)
}

@inline(never)
@MainActor
private func resolveStoredModifierView<Content: View>(
  _ content: Content,
  authoringScope: CapturedSubviewScope,
  in context: ResolveContext
) -> ResolveWork<ResolvedNode> {
  withAuthoringContext(authoringScope.authoringContext) {
    resolveViewWork(content, in: context)
  }
}

public struct BackgroundModifier<BackgroundContent: View>: IterativePrimitiveViewModifier {
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

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    return resolveStoredModifierView(
      background,
      authoringScope: backgroundAuthoringScope,
      in: context.child(component: .named("background"))
    ).flatMap { backgroundNode in
      return resolveModifierContent(
        content,
        in: context.child(component: .named("base"))
      ).map { baseNode in
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
  }
}
