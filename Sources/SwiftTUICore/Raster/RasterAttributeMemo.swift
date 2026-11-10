/// Per-raster scratch that lets the cells of a run share one
/// ``RasterCellAttributes``.
///
/// Painters hand the cell writer a style per cell, and the writer composites
/// that style over whatever the cell already holds. A text line or a fill row
/// repeats the same inputs for every cell, so each step keeps its most recent
/// answer: a hit reuses the attributes object the previous cell received
/// instead of resolving, compositing and allocating again. A miss computes the
/// reference result, so a hit and a miss always produce equal cells.
///
/// The keys are object identities wherever the input is already shared
/// (the cell's current attributes, a boxed overlay) and values only where the
/// caller holds a style by value. Identity keys are held strongly, so an
/// identity cannot be reused while it is a key.
///
/// One instance serves one rasterization on one thread.
final class RasterAttributeMemo {
  // MARK: Boxing a style held by value

  private var hasBoxed = false
  private var boxedStyle: ResolvedTextStyle?
  private var boxedHyperlink: String?
  private var boxed: RasterCellAttributes?

  /// Attributes for a style and hyperlink the caller holds by value.
  func attributes(
    style: ResolvedTextStyle?,
    hyperlink: String?
  ) -> RasterCellAttributes? {
    guard style != nil || hyperlink != nil else {
      return nil
    }
    if hasBoxed, boxedStyle == style, Self.sameBytes(boxedHyperlink, hyperlink) {
      return boxed
    }
    let made = RasterCellAttributes.make(style: style, hyperlink: hyperlink)
    hasBoxed = true
    boxedStyle = style
    boxedHyperlink = hyperlink
    boxed = made
    return made
  }

  /// Byte equality, not canonical equivalence: a hyperlink reaches the host
  /// with its authored UTF-8, so two spellings of one destination must not
  /// share attributes.
  private static func sameBytes(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      true
    case (let lhs?, let rhs?):
      lhs.utf8.elementsEqual(rhs.utf8)
    default:
      false
    }
  }

  // MARK: Compositing an overlay over a cell's current attributes

  private var hasComposite = false
  private var compositeOverlay: RasterCellAttributes?
  private var compositeUnderlay: RasterCellAttributes?
  private var compositeBlendMode: BlendMode?
  private var compositeResult: RasterCellAttributes?

  func composite(
    overlay: RasterCellAttributes?,
    underlay: RasterCellAttributes?,
    blendMode: BlendMode?
  ) -> RasterCellAttributes?? {
    guard hasComposite, compositeOverlay === overlay, compositeUnderlay === underlay,
      compositeBlendMode == blendMode
    else {
      return nil
    }
    return .some(compositeResult)
  }

  func recordComposite(
    overlay: RasterCellAttributes?,
    underlay: RasterCellAttributes?,
    blendMode: BlendMode?,
    result: RasterCellAttributes?
  ) {
    hasComposite = true
    compositeOverlay = overlay
    compositeUnderlay = underlay
    compositeBlendMode = blendMode
    compositeResult = result
  }

  // MARK: Tinting a cell's current attributes

  private var hasTint = false
  private var tintUnderlay: RasterCellAttributes?
  private var tintColor: Color?
  private var tintResult: RasterCellAttributes?

  func tint(
    underlay: RasterCellAttributes?,
    color: Color
  ) -> RasterCellAttributes?? {
    guard hasTint, tintUnderlay === underlay, tintColor == color else {
      return nil
    }
    return .some(tintResult)
  }

  func recordTint(
    underlay: RasterCellAttributes?,
    color: Color,
    result: RasterCellAttributes?
  ) {
    hasTint = true
    tintUnderlay = underlay
    tintColor = color
    tintResult = result
  }
}

/// The most recent text style a text painter resolved, keyed by what it was
/// resolved against.
///
/// A resolved text style depends on the authored style, the colour modes, and
/// the background already in the cell. When the colour modes do not sample by
/// position, every cell of a run that sits on the same underlying attributes
/// resolves to the same style, so the run resolves once per distinct underlay
/// instead of once per cell.
struct RasterTextStyleMemo {
  private var hasEntry = false
  private var run: Int?
  private var underlay: RasterCellAttributes?
  private var resolved: RasterCellAttributes?

  /// The attributes resolved for `run` over `underlay`, when they are current.
  func attributes(
    run: Int?,
    underlay: RasterCellAttributes?
  ) -> RasterCellAttributes?? {
    guard hasEntry, self.run == run, self.underlay === underlay else {
      return nil
    }
    return .some(resolved)
  }

  mutating func record(
    run: Int?,
    underlay: RasterCellAttributes?,
    resolved: RasterCellAttributes?
  ) {
    hasEntry = true
    self.run = run
    self.underlay = underlay
    self.resolved = resolved
  }
}
