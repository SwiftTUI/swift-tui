/// The layout strategy applied to a resolved node.
package enum LayoutBehavior: Sendable {
  case intrinsic
  case stack(
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  )
  case lazyStack(
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  )
  case overlay(alignment: Alignment)
  case padding(EdgeInsets)
  /// Expands child layout back into the container safe area reserved by an
  /// ancestor wrapper while leaving the wrapper's own measured size unchanged.
  case safeAreaIgnoring(EdgeInsets)
  /// Inserts a secondary child along one safe-area edge and shifts the primary
  /// child inward only when the inset content exceeds the reclaimed safe area.
  case safeAreaInset(edge: Edge, alignment: Alignment, spacing: Int, safeArea: EdgeInsets)
  /// A border that reserves layout insets for its own glyphs.
  ///
  /// For `.outset` placements the layout engine
  /// treats this like a `.padding` whose insets are derived from the
  /// border set's per-side display widths (masked by `sides`), so the
  /// child's content is never occluded by border glyphs.  For `.inset`
  /// placements the border contributes no layout space — glyphs will be
  /// painted into the view's outermost cells by the rasterizer.
  ///
  /// The styling payload (`foreground`, `background`, `blend`,
  /// `blendPhase`) passes through the layout pass untouched and is
  /// consumed later by the rasterizer.  See §4.7 of
  /// `SHAPE_AND_BORDER_APIS.md` for the full design.
  ///
  /// Marked `indirect` so the aggregate payload (BorderSet +
  /// BorderEdgeStyle + BorderBackgroundStyle + BorderBlend + sides)
  /// stays behind a single pointer inside the enum discriminant;
  /// unboxed, this case would balloon ``LayoutBehavior`` past 1.6 kB
  /// and overflow the stack during deep recursive tree traversals
  /// (see the 1024-deep ResolvedNode regression tests).
  indirect case border(
    BorderSet,
    placement: StrokeStyle.Placement,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set
  )
  case frame(width: Int?, height: Int?, alignment: Alignment)
  case offset(x: Int, y: Int)
  /// Positions the content so its center lands at `(x, y)` in the
  /// parent's coordinate space.  Unlike `.offset`, which translates
  /// the content without affecting parent layout, `.position` takes
  /// the full proposed size for its wrapper so the parent reserves
  /// space for the absolute placement area.  Matches SwiftUI's
  /// `View.position(x:y:)` semantics.
  case position(x: Int, y: Int)
  case flexibleFrame(
    minWidth: ProposedDimension?, idealWidth: ProposedDimension?, maxWidth: ProposedDimension?,
    minHeight: ProposedDimension?, idealHeight: ProposedDimension?, maxHeight: ProposedDimension?,
    alignment: Alignment
  )
  case decoration(primaryIndex: Int, alignment: Alignment)
  case viewThatFits(AxisSet)
  case custom(CustomLayoutHandle)
}

extension LayoutBehavior: Equatable {
  package static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.intrinsic, .intrinsic):
      return true
    case (.overlay(let lhsAlignment), .overlay(let rhsAlignment)):
      return lhsAlignment == rhsAlignment
    case (
      .stack(let lhsAxis, let lhsSpacing, let lhsHorizontalAlignment, let lhsVerticalAlignment),
      .stack(let rhsAxis, let rhsSpacing, let rhsHorizontalAlignment, let rhsVerticalAlignment)
    ):
      return lhsAxis == rhsAxis
        && lhsSpacing == rhsSpacing
        && lhsHorizontalAlignment == rhsHorizontalAlignment
        && lhsVerticalAlignment == rhsVerticalAlignment
    case (
      .lazyStack(let lhsAxis, let lhsSpacing, let lhsHorizontalAlignment, let lhsVerticalAlignment),
      .lazyStack(let rhsAxis, let rhsSpacing, let rhsHorizontalAlignment, let rhsVerticalAlignment)
    ):
      return lhsAxis == rhsAxis
        && lhsSpacing == rhsSpacing
        && lhsHorizontalAlignment == rhsHorizontalAlignment
        && lhsVerticalAlignment == rhsVerticalAlignment
    case (.padding(let lhsInsets), .padding(let rhsInsets)):
      return lhsInsets == rhsInsets
    case (.safeAreaIgnoring(let lhsInsets), .safeAreaIgnoring(let rhsInsets)):
      return lhsInsets == rhsInsets
    case (
      .safeAreaInset(
        edge: let lhsEdge,
        alignment: let lhsAlignment,
        spacing: let lhsSpacing,
        safeArea: let lhsSafeArea
      ),
      .safeAreaInset(
        edge: let rhsEdge,
        alignment: let rhsAlignment,
        spacing: let rhsSpacing,
        safeArea: let rhsSafeArea
      )
    ):
      return lhsEdge == rhsEdge
        && lhsAlignment == rhsAlignment
        && lhsSpacing == rhsSpacing
        && lhsSafeArea == rhsSafeArea
    case (
      .border(
        let lhsSet, let lhsPlacement, let lhsFg, let lhsBg,
        let lhsBlend, let lhsPhase, let lhsSides
      ),
      .border(
        let rhsSet, let rhsPlacement, let rhsFg, let rhsBg,
        let rhsBlend, let rhsPhase, let rhsSides
      )
    ):
      return lhsSet == rhsSet
        && lhsPlacement == rhsPlacement
        && lhsFg == rhsFg
        && lhsBg == rhsBg
        && lhsBlend == rhsBlend
        && lhsPhase == rhsPhase
        && lhsSides == rhsSides
    case (
      .frame(let lhsWidth, let lhsHeight, let lhsAlignment),
      .frame(let rhsWidth, let rhsHeight, let rhsAlignment)
    ):
      return lhsWidth == rhsWidth
        && lhsHeight == rhsHeight
        && lhsAlignment == rhsAlignment
    case (.offset(let lhsX, let lhsY), .offset(let rhsX, let rhsY)):
      return lhsX == rhsX && lhsY == rhsY
    case (.position(let lhsX, let lhsY), .position(let rhsX, let rhsY)):
      return lhsX == rhsX && lhsY == rhsY
    case (
      .flexibleFrame(
        let lhsMinW, let lhsIdealW, let lhsMaxW,
        let lhsMinH, let lhsIdealH, let lhsMaxH,
        let lhsAlignment
      ),
      .flexibleFrame(
        let rhsMinW, let rhsIdealW, let rhsMaxW,
        let rhsMinH, let rhsIdealH, let rhsMaxH,
        let rhsAlignment
      )
    ):
      return lhsMinW == rhsMinW && lhsIdealW == rhsIdealW && lhsMaxW == rhsMaxW
        && lhsMinH == rhsMinH && lhsIdealH == rhsIdealH && lhsMaxH == rhsMaxH
        && lhsAlignment == rhsAlignment
    case (
      .decoration(let lhsPrimaryIndex, let lhsAlignment),
      .decoration(let rhsPrimaryIndex, let rhsAlignment)
    ):
      return lhsPrimaryIndex == rhsPrimaryIndex
        && lhsAlignment == rhsAlignment
    case (.viewThatFits(let lhsAxes), .viewThatFits(let rhsAxes)):
      return lhsAxes == rhsAxes
    case (.custom(let lhsHandle), .custom(let rhsHandle)):
      return lhsHandle == rhsHandle
    default:
      return false
    }
  }
}

/// Modifier-driven layout metadata attached to a resolved node.

extension LayoutBehavior {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    if self == other {
      return true
    }

    // `.border` measurement depends on the chosen ``BorderSet``,
    // the ``Placement``, and the active ``Edge.Set`` — all three feed
    // ``borderLayoutInsets``, the single function the layout engine
    // consults at lines 489 and 733 of ``LayoutEngine``.
    // Specifically: `.inset` placement returns zero ``EdgeInsets()``,
    // while `.outset` returns non-zero insets, so two borders with
    // identical set and sides but different placement produce different
    // measured sizes and must not be treated as equivalent.
    // The other payload fields (foreground color, background color,
    // blend, blendPhase) are draw-time concerns: the rasterizer reads
    // them when painting glyphs, but they never change a node's measured
    // size or its child proposal.
    //
    // Treating two borders that differ only in those cosmetic fields as
    // measurement-equivalent lets the layout cache reuse measurements
    // across animation ticks that interpolate ``blendPhase``: each
    // tick mutates the phase on the resolved tree, and without this
    // carve-out the cache (and the retained-layout cache, which routes
    // through this same predicate via
    // ``ResolvedNode.isEquivalentForPlacement``) would invalidate on
    // every frame.  That cascades up the ancestor chain because each
    // ancestor's ``isEquivalentForMeasurement`` walks its children.
    if case .border(let lhsSet, let lhsPlacement, _, _, _, _, let lhsSides) = self,
      case .border(let rhsSet, let rhsPlacement, _, _, _, _, let rhsSides) = other
    {
      return lhsSet == rhsSet && lhsPlacement == rhsPlacement && lhsSides == rhsSides
    }

    guard case .custom(let lhsHandle) = self,
      case .custom(let rhsHandle) = other,
      let lhsSignature = lhsHandle.measurementReuseSignature,
      let rhsSignature = rhsHandle.measurementReuseSignature
    else {
      return false
    }

    return lhsSignature == rhsSignature
  }

  package func isEquivalentForPlacement(
    to other: Self
  ) -> Bool {
    if self == other {
      return true
    }

    if case .border(let lhsSet, let lhsPlacement, _, _, _, _, let lhsSides) = self,
      case .border(let rhsSet, let rhsPlacement, _, _, _, _, let rhsSides) = other
    {
      return lhsSet == rhsSet && lhsPlacement == rhsPlacement && lhsSides == rhsSides
    }

    guard case .custom(let lhsHandle) = self,
      case .custom(let rhsHandle) = other,
      let lhsSignature = lhsHandle.placementReuseSignature,
      let rhsSignature = rhsHandle.placementReuseSignature
    else {
      return false
    }

    return lhsSignature == rhsSignature
  }
}
