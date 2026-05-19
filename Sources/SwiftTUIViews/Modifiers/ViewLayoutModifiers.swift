public import SwiftTUICore

// The public layout modifier API.
//
// This `extension View` is the fluent catalogue of layout modifiers consumers
// call — `.padding()`, `.frame()`, `.offset()`, `.overlay()`, and so on. Each
// method constructs the matching `PrimitiveViewModifier` value; those
// implementation types live in `ViewLayoutModifierTypes.swift`.

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
