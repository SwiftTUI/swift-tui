// Translated-projection equality for draw commands (scroll-latency R3.2b).
//
// The translation-hypothesis walk needs to answer "does `current` paint
// exactly what `previous` painted, `dy` screen rows lower?" without building
// translated copies. Every painter in the raster tier resolves its content in
// bounds-relative coordinates — gradients, tiles, glyph layout, shape
// geometry (unit-rect paths) — so a command whose payload is equal and whose
// bounds are equal-under-shift rasterizes to the shifted cells. The exceptions
// are commands with surface-level side effects or opaque payloads: images
// (attachment sidecar + Kitty bookkeeping), canvas (author closure), and
// foreign surfaces (payload excluded from `==`); those never match and fall
// out as repaint rows.

extension CellRect {
  package func offsetBy(dy: Int) -> CellRect {
    CellRect(
      origin: CellPoint(x: origin.x, y: origin.y + dy),
      size: size
    )
  }

  /// The half-open row range this rect covers.
  package var rows: Range<Int> {
    origin.y..<(origin.y + max(0, size.height))
  }

  /// The half-open column range this rect covers.
  package var columns: Range<Int> {
    origin.x..<(origin.x + max(0, size.width))
  }
}

extension DrawCommand {
  /// The command's own top-level bounds (nested children excluded).
  package var topLevelBounds: CellRect {
    switch self {
    case .group(let bounds, _),
      .text(let bounds, _, _, _, _, _),
      .preformattedText(let bounds, _, _),
      .styledPreformattedText(let bounds, _, _),
      .richText(let bounds, _, _, _, _),
      .image(let bounds, _, _),
      .fill(let bounds, _, _, _, _),
      .stroke(let bounds, _, _, _, _, _, _),
      .rule(let bounds, _, _, _),
      .border(let bounds, _, _, _, _, _, _),
      .canvas(let bounds, _, _),
      .foreignSurface(let bounds, _),
      .clip(let bounds, _):
      bounds
    }
  }

  /// Whether `current` paints exactly this command's output shifted down by
  /// `dy` rows. Conservative: `false` never mis-serves — it only moves rows
  /// onto the repaint path.
  package func paintsTranslated(by dy: Int, as current: DrawCommand) -> Bool {
    switch (self, current) {
    case (.group(let pBounds, let pChildren), .group(let cBounds, let cChildren)):
      guard cBounds == pBounds.offsetBy(dy: dy), pChildren.count == cChildren.count else {
        return false
      }
      for (previousChild, currentChild) in zip(pChildren, cChildren)
      where !previousChild.paintsTranslated(by: dy, as: currentChild) {
        return false
      }
      return true
    case (.clip(let pBounds, let pChild), .clip(let cBounds, let cChild)):
      return cBounds == pBounds.offsetBy(dy: dy) && pChild.paintsTranslated(by: dy, as: cChild)
    case (
      .text(let pBounds, let pContent, let pStyle, let pLimit, let pTruncation, let pWrap),
      .text(let cBounds, let cContent, let cStyle, let cLimit, let cTruncation, let cWrap)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pContent == cContent
        && pStyle == cStyle
        && pLimit == cLimit
        && pTruncation == cTruncation
        && pWrap == cWrap
    case (
      .preformattedText(let pBounds, let pLines, let pStyle),
      .preformattedText(let cBounds, let cLines, let cStyle)
    ):
      return cBounds == pBounds.offsetBy(dy: dy) && pLines == cLines && pStyle == cStyle
    case (
      .styledPreformattedText(let pBounds, let pLines, let pStyle),
      .styledPreformattedText(let cBounds, let cLines, let cStyle)
    ):
      return cBounds == pBounds.offsetBy(dy: dy) && pLines == cLines && pStyle == cStyle
    case (
      .richText(let pBounds, let pPayload, let pLimit, let pTruncation, let pWrap),
      .richText(let cBounds, let cPayload, let cLimit, let cTruncation, let cWrap)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pPayload == cPayload
        && pLimit == cLimit
        && pTruncation == cTruncation
        && pWrap == cWrap
    case (
      .fill(let pBounds, let pGeometry, let pInset, let pStyle, let pMode),
      .fill(let cBounds, let cGeometry, let cInset, let cStyle, let cMode)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pGeometry == cGeometry
        && pInset == cInset
        && pStyle == cStyle
        && pMode == cMode
    case (
      .stroke(
        let pBounds, let pGeometry, let pInset, let pStyle, let pStroke, let pBorder,
        let pBackground),
      .stroke(
        let cBounds, let cGeometry, let cInset, let cStyle, let cStroke, let cBorder,
        let cBackground)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pGeometry == cGeometry
        && pInset == cInset
        && pStyle == cStyle
        && pStroke == cStroke
        && pBorder == cBorder
        && pBackground == cBackground
    case (
      .rule(let pBounds, let pStyle, let pStroke, let pAxis),
      .rule(let cBounds, let cStyle, let cStroke, let cAxis)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pStyle == cStyle
        && pStroke == cStroke
        && pAxis == cAxis
    case (
      .border(
        let pBounds, let pSet, let pForeground, let pBackground, let pBlend, let pPhase,
        let pSides),
      .border(
        let cBounds, let cSet, let cForeground, let cBackground, let cBlend, let cPhase,
        let cSides)
    ):
      return cBounds == pBounds.offsetBy(dy: dy)
        && pSet == cSet
        && pForeground == cForeground
        && pBackground == cBackground
        && pBlend == cBlend
        && pPhase == cPhase
        && pSides == cSides
    case (.image, _), (.canvas, _), (.foreignSurface, _):
      // Images carry attachment/graphics side effects the blit does not
      // translate; canvas and foreign-surface payloads are opaque (author
      // closures / identity-only equality). Never served by translation.
      return false
    default:
      return false
    }
  }

  /// A conservative decomposition of the cells this command can ink, used for
  /// repaint-relevance tests. For ring-shaped chrome (an un-filled rectangle
  /// stroke or a layout border without background) the interior is empty, so
  /// the decomposition returns the perimeter strips — that is what lets a
  /// static container border beside a scrolling band avoid tainting every
  /// band row its bounding box covers. Everything else reports its bounds.
  package var inkRects: [CellRect] {
    switch self {
    case .stroke(let bounds, .rectangle, 0, _, let strokeStyle, _, nil):
      return Self.perimeterRects(of: bounds, thickness: max(1, strokeStyle.lineWidth))
    case .border(let bounds, _, _, nil, _, _, let sides):
      var rects: [CellRect] = []
      if sides.contains(.top) {
        rects.append(
          CellRect(origin: bounds.origin, size: CellSize(width: bounds.size.width, height: 1)))
      }
      if sides.contains(.bottom), bounds.size.height > 1 {
        rects.append(
          CellRect(
            origin: CellPoint(x: bounds.origin.x, y: bounds.maxY - 1),
            size: CellSize(width: bounds.size.width, height: 1)))
      }
      if sides.contains(.leading) {
        rects.append(
          CellRect(origin: bounds.origin, size: CellSize(width: 1, height: bounds.size.height)))
      }
      if sides.contains(.trailing), bounds.size.width > 1 {
        rects.append(
          CellRect(
            origin: CellPoint(x: bounds.maxX - 1, y: bounds.origin.y),
            size: CellSize(width: 1, height: bounds.size.height)))
      }
      return rects.isEmpty ? [bounds] : rects
    case .group(let bounds, let children):
      let childRects = children.flatMap(\.inkRects)
      return childRects.isEmpty ? [bounds] : childRects
    case .clip(_, let child):
      return child.inkRects
    default:
      return [topLevelBounds]
    }
  }

  /// Structural row-invariance for static chrome (scroll-latency R3.2b): a
  /// command whose per-row ink is identical for every row of `rect` more than
  /// `edge` rows from its top/bottom edges. Under a band blit such a
  /// command's interior contribution at row `y` equals its contribution at
  /// the source row `y − dy` — no repaint needed — while its edge zone
  /// (corners, boundary glyphs, half-block reach) stays on the repaint path.
  ///
  /// Qualifies only shapes whose vertical extent is literally uniform:
  /// rectangles and rounded rectangles (the corner zone is the edge), filled
  /// fully or to the stroke interior, with position-independent styles
  /// (semantic roles and colors — gradients, tiles, and terminal-chrome
  /// styles sample by position and disqualify).
  package func verticalRowInvariance(
    in environment: StyleEnvironmentSnapshot
  ) -> (rect: CellRect, edge: Int)? {
    func edgeZone(_ geometry: ShapeGeometry, insetAmount: Int) -> Int? {
      switch geometry {
      case .rectangle:
        max(1, 1 + insetAmount)
      case .roundedRectangle(let cornerRadius):
        max(1, cornerRadius + 1 + insetAmount)
      default:
        nil
      }
    }
    switch self {
    case .fill(let bounds, let geometry, let insetAmount, let style, _)
    where style.isPositionIndependent(in: environment):
      // Both fill modes paint row-uniform interiors for these geometries.
      guard let edge = edgeZone(geometry, insetAmount: insetAmount) else {
        return nil
      }
      return (bounds, edge)
    case .stroke(
      let bounds, let geometry, let insetAmount, let style, _, _, let backgroundStyle)
    where style.isPositionIndependent(in: environment):
      if let backgroundStyle {
        for sideStyle in [
          backgroundStyle.top, backgroundStyle.right, backgroundStyle.bottom,
          backgroundStyle.left,
        ] {
          if let sideStyle, !sideStyle.isPositionIndependent(in: environment) {
            return nil
          }
        }
      }
      guard let edge = edgeZone(geometry, insetAmount: insetAmount) else {
        return nil
      }
      return (bounds, edge)
    default:
      return nil
    }
  }

  private static func perimeterRects(of bounds: CellRect, thickness: Int) -> [CellRect] {
    let width = bounds.size.width
    let height = bounds.size.height
    guard height > 2 * thickness, width > 2 * thickness else {
      return [bounds]
    }
    return [
      CellRect(origin: bounds.origin, size: CellSize(width: width, height: thickness)),
      CellRect(
        origin: CellPoint(x: bounds.origin.x, y: bounds.maxY - thickness),
        size: CellSize(width: width, height: thickness)),
      CellRect(
        origin: CellPoint(x: bounds.origin.x, y: bounds.origin.y + thickness),
        size: CellSize(width: thickness, height: height - 2 * thickness)),
      CellRect(
        origin: CellPoint(x: bounds.maxX - thickness, y: bounds.origin.y + thickness),
        size: CellSize(width: thickness, height: height - 2 * thickness)),
    ]
  }
}

extension AnyShapeStyle {
  /// Whether every cell this style resolves is independent of the cell's
  /// position, resolving indirections (semantic roles, terminal chrome)
  /// through the same environment snapshot the painter will use. Gradients,
  /// tiles, and any indirection that bottoms out in them are not.
  package func isPositionIndependent(
    in environment: StyleEnvironmentSnapshot,
    depth: Int = 0
  ) -> Bool {
    guard depth < 4 else {
      return false
    }
    switch self {
    case .color:
      return true
    case .opacity(let wrapped, _):
      return wrapped.isPositionIndependent(in: environment, depth: depth + 1)
    case .semantic(let role):
      let resolved = environment.resolvedStyle(for: role)
      if resolved == self {
        // The painter falls back to the theme's palette entry for a
        // self-resolving role; palette fallbacks are colors.
        return true
      }
      return resolved.isPositionIndependent(in: environment, depth: depth + 1)
    case .terminalChrome(let chromeStyle):
      return environment.theme.resolvedStyle(
        for: chromeStyle,
        appearance: environment.appearance
      ).isPositionIndependent(in: environment, depth: depth + 1)
    case .linearGradient, .radialGradient, .meshGradient, .tileStyle:
      return false
    }
  }
}

extension DrawNode {
  /// Whether `current`'s entire subtree paints this subtree's output shifted
  /// down by `dy` rows: identity-matched, bounds and explicit clips shifted,
  /// styles/metadata/environment equal, every command translated, no draw
  /// effects (effect output may sample beyond the one-cell reach the walk's
  /// dilation covers, and effect-carrying fragments record presentation-layer
  /// state the blit does not translate).
  ///
  /// Explicit stack, not recursion: draw trees are as deep as the authored
  /// view hierarchy and the frame tail runs on 512 KiB worker stacks.
  package func paintsSubtreeTranslated(by dy: Int, as current: DrawNode) -> Bool {
    var stack: [(previous: DrawNode, current: DrawNode)] = [(self, current)]
    while let (previous, current) = stack.popLast() {
      guard previous.identity == current.identity,
        previous.subtreeNodeCount == current.subtreeNodeCount,
        current.bounds == previous.bounds.offsetBy(dy: dy),
        previous.drawEffects.isEmpty,
        current.drawEffects.isEmpty,
        previous.metadata == current.metadata,
        previous.environmentSnapshot == current.environmentSnapshot,
        previous.children.count == current.children.count,
        previous.commands.count == current.commands.count,
        previous.postCommands.count == current.postCommands.count
      else {
        return false
      }
      switch (previous.clipBounds, current.clipBounds) {
      case (nil, nil):
        break
      case (.some(let previousClip), .some(let currentClip))
      where currentClip == previousClip.offsetBy(dy: dy) || currentClip == previousClip:
        // A clip that translates with the subtree preserves the projection
        // wholesale. A *static* clip (a viewport) is also sound for the rows
        // the walk serves: kept band rows and their sources both sit inside
        // the band, which is the viewport intersected with the surface, so
        // the clip cuts neither end of the translation; the clipped edges
        // outside the band stay on the ordinary damage path.
        break
      default:
        return false
      }
      for (previousCommand, currentCommand) in zip(previous.commands, current.commands)
      where !previousCommand.paintsTranslated(by: dy, as: currentCommand) {
        return false
      }
      for (previousCommand, currentCommand) in zip(previous.postCommands, current.postCommands)
      where !previousCommand.paintsTranslated(by: dy, as: currentCommand) {
        return false
      }
      for pair in zip(previous.children, current.children) {
        stack.append(pair)
      }
    }
    return true
  }
}
