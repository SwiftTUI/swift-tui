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

  /// Limits the lines of every descendant text run, matching SwiftUI's
  /// environment contract: the innermost write wins and `nil` clears an
  /// inherited limit. The raw value travels in the environment; text layout
  /// clamps non-positive limits to one line.
  public func lineLimit(_ limit: Int?) -> some View {
    environment(\.lineLimit, limit)
  }

  public func truncationMode(_ mode: Text.TruncationMode) -> some View {
    environment(\.truncationMode, mode)
  }

  public func textWrappingStrategy(_ strategy: Text.WrappingStrategy) -> some View {
    environment(\.textWrappingStrategy, strategy)
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
  /// ``offset(x:y:)`` translates the view without affecting parent layout.
  /// In contrast, `.position` wraps the view in a container that takes the full proposed space.
  /// Thus, the parent reserves room for the absolute placement area.
  /// This behavior matches SwiftUI `View.position(x:y:)`.
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

  /// Tags this view with a matched-geometry key.
  /// The animation controller uses this key across conditional re-creation.
  /// For example, `if` and `else` branches can swap between two layouts.
  /// The controller animates the transition as one view that moves between the locations.
  ///
  /// Matches SwiftUI's `.matchedGeometryEffect(id:in:properties:anchor:isSource:)`
  /// API shape.  Scope keys with `@Namespace` or pass a
  /// `MatchedGeometryNamespace` value explicitly.
  ///
  /// `properties` selects what interpolates: `.frame` (the default) slides
  /// the view's `anchor` point from the source's to the destination's and
  /// resizes its bounds between the two sizes; `.position` only slides;
  /// `.size` only resizes in place around the anchor.
  ///
  /// Size interpolates at the placed level, by bounds and clip, not by
  /// re-layout: the content lays out once at its destination size and is
  /// clipped to the interpolated rect while it grows or shrinks, and every
  /// descendant whose bounds coincide with the matched node's (a
  /// `.background`, an overlay, full-frame chrome) resizes with it. Tag the
  /// outermost node whose chrome should follow,
  /// `.background(...).border(...).matchedGeometryEffect(...)`, since the
  /// modifier tags its content.
  ///
  /// `isSource: false` lets you have multiple views with the same
  /// key where only the designated source view contributes its
  /// geometry as the "from" reference. A non-source instance receives the
  /// match when the key swaps to it between frames; an instance that is on
  /// screen together with its source is not positioned onto the source.
  public func matchedGeometryEffect<ID: Hashable>(
    id: ID,
    in namespace: MatchedGeometryNamespace = .default,
    properties: MatchedGeometryProperties = .frame,
    anchor: UnitPoint = .center,
    isSource: Bool = true
  ) -> some View {
    modifier(
      MatchedGeometryModifier(
        config: MatchedGeometryConfig(
          key: MatchedGeometryKey(namespace: namespace, id: id),
          isSource: isSource,
          properties: properties,
          anchor: anchor
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

  /// SwiftUI's labeled spelling. Terminal safe areas have a single region,
  /// so only the edge set participates.
  public func ignoresSafeArea(
    edges: Edge.Set
  ) -> some View {
    ignoresSafeArea(edges)
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
        insetAuthoringScope: makeCapturedSubviewScope()
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
        overlayAuthoringScope: makeCapturedSubviewScope()
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
        backgroundAuthoringScope: makeCapturedSubviewScope()
      )
    )
  }
}
