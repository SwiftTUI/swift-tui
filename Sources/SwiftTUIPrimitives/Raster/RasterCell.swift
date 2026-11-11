/// A single terminal cell in a rasterized surface.
///
/// A surface holds one cell per column per row, and the rasterizer, the damage
/// diffs and every host encoder copy and compare cells in bulk. The cell
/// therefore stores only its glyph and its two column counts inline; the
/// resolved style and the hyperlink live in a shared, immutable
/// ``RasterCellAttributes`` object that a run of identically styled cells
/// references. Copying a cell copies 32 bytes, and two cells that reference
/// the same attributes compare without reading the style.
///
/// `style` and `hyperlink` remain ordinary read-write properties. Assigning
/// either one gives the cell its own attributes; writers that style many cells
/// alike build one ``RasterCellAttributes`` and share it.
public struct RasterCell: Equatable, Sendable {
  public var character: Character

  /// Shared style, hyperlink and exceptional full-width column values.
  ///
  /// Ordinary unstyled, unlinked cells need no attributes object.
  package var attributes: RasterCellAttributes?

  private var storedSpanWidth: Int32
  private var storedContinuationLeadX: Int32

  /// The stored value that stands for "not a continuation cell".
  private static let noContinuationLead = Int32.min
  private static let overflowContinuationLead = Int32.min + 1

  /// The number of columns the cell's glyph covers: `1` for a narrow glyph,
  /// the glyph's width on the lead cell of a wide glyph, and `0` on the
  /// continuation cells that follow it.
  ///
  /// All `Int` values round-trip. Counts outside the inline range use shared
  /// attributes storage without increasing the size of an ordinary cell.
  public var spanWidth: Int {
    get {
      storedSpanWidth == .min
        ? attributes?.spanWidthOverflow ?? Int(Int32.min) : Int(storedSpanWidth)
    }
    set {
      attributes = Self.withCounts(
        attributes, spanWidth: newValue, continuationLeadX: continuationLeadX)
      storedSpanWidth = Int32(exactly: newValue) ?? .min
    }
  }

  /// The column of the wide glyph this cell continues, or `nil` when the cell
  /// starts its own glyph.
  ///
  /// All `Int` values, including the inline storage's reserved sentinels,
  /// round-trip distinctly from `nil`.
  public var continuationLeadX: Int? {
    get {
      if storedContinuationLeadX == Self.noContinuationLead { return nil }
      if storedContinuationLeadX == Self.overflowContinuationLead {
        return attributes?.continuationLeadXOverflow
      }
      return Int(storedContinuationLeadX)
    }
    set {
      attributes = Self.withCounts(attributes, spanWidth: spanWidth, continuationLeadX: newValue)
      storedContinuationLeadX = Self.storedLead(newValue)
    }
  }

  public var style: ResolvedTextStyle? {
    get { attributes?.style }
    set {
      attributes = RasterCellAttributes.make(
        style: newValue, hyperlink: attributes?.hyperlink,
        spanWidthOverflow: attributes?.spanWidthOverflow,
        continuationLeadXOverflow: attributes?.continuationLeadXOverflow)
    }
  }

  public var hyperlink: String? {
    get { attributes?.hyperlink }
    set {
      attributes = RasterCellAttributes.make(
        style: attributes?.style, hyperlink: newValue,
        spanWidthOverflow: attributes?.spanWidthOverflow,
        continuationLeadXOverflow: attributes?.continuationLeadXOverflow)
    }
  }

  public init(
    character: Character = " ",
    spanWidth: Int = 1,
    continuationLeadX: Int? = nil,
    style: ResolvedTextStyle? = nil,
    hyperlink: String? = nil
  ) {
    self.character = character
    self.storedSpanWidth = Int32(exactly: spanWidth) ?? .min
    self.storedContinuationLeadX = Self.storedLead(continuationLeadX)
    self.attributes = RasterCellAttributes.make(
      style: style, hyperlink: hyperlink,
      spanWidthOverflow: Self.spanOverflow(spanWidth),
      continuationLeadXOverflow: Self.leadOverflow(continuationLeadX))
  }

  /// Creates a cell that shares `attributes` with the other cells of its run.
  package init(
    character: Character,
    spanWidth: Int = 1,
    continuationLeadX: Int? = nil,
    attributes: RasterCellAttributes?
  ) {
    self.character = character
    self.storedSpanWidth = Int32(exactly: spanWidth) ?? .min
    self.storedContinuationLeadX = Self.storedLead(continuationLeadX)
    self.attributes = Self.withCounts(
      attributes, spanWidth: spanWidth, continuationLeadX: continuationLeadX)
  }

  public static let empty = Self()

  public var isContinuation: Bool {
    storedContinuationLeadX != Self.noContinuationLead
  }

  /// Whether the cell is exactly ``empty``: an unstyled, unlinked space that
  /// starts its own one-column glyph.
  package var isEmpty: Bool {
    attributes == nil && storedSpanWidth == 1
      && storedContinuationLeadX == Self.noContinuationLead && character == " "
  }

  public static func == (lhs: RasterCell, rhs: RasterCell) -> Bool {
    lhs.storedSpanWidth == rhs.storedSpanWidth
      && lhs.storedContinuationLeadX == rhs.storedContinuationLeadX
      && RasterCellAttributes.areEqual(lhs.attributes, rhs.attributes)
      && lhs.character == rhs.character
  }

  private static func storedLead(_ lead: Int?) -> Int32 {
    guard let lead else {
      return noContinuationLead
    }
    guard let value = Int32(exactly: lead), value > overflowContinuationLead else {
      return overflowContinuationLead
    }
    return value
  }

  private static func spanOverflow(_ width: Int) -> Int? {
    Int32(exactly: width) == nil ? width : nil
  }

  private static func leadOverflow(_ lead: Int?) -> Int? {
    guard let lead else { return nil }
    return storedLead(lead) == overflowContinuationLead ? lead : nil
  }

  private static func withCounts(
    _ attributes: RasterCellAttributes?, spanWidth: Int, continuationLeadX: Int?
  ) -> RasterCellAttributes? {
    let spanOverflow = Self.spanOverflow(spanWidth)
    let leadOverflow = Self.leadOverflow(continuationLeadX)
    guard
      attributes?.spanWidthOverflow != spanOverflow
        || attributes?.continuationLeadXOverflow != leadOverflow
    else { return attributes }
    return RasterCellAttributes.make(
      style: attributes?.style, hyperlink: attributes?.hyperlink,
      spanWidthOverflow: spanOverflow, continuationLeadXOverflow: leadOverflow)
  }

  /// Whether both cells have the same inline count encodings. Exceptional
  /// full-width values are compared by the attributes equality that follows.
  @inline(__always)
  fileprivate func hasSameSpan(as other: RasterCell) -> Bool {
    storedSpanWidth == other.storedSpanWidth
      && storedContinuationLeadX == other.storedContinuationLeadX
  }

  /// Whether two rows are the same buffer, and therefore hold the same cells.
  ///
  /// Incremental rasterization carries an untouched row over from the previous
  /// surface without copying it, so a diff answers "unchanged" for such a row
  /// without reading a cell. Rows in different buffers can still be equal.
  package static func rowsShareStorage(_ lhs: [RasterCell], _ rhs: [RasterCell]) -> Bool {
    guard lhs.count == rhs.count else {
      return false
    }
    guard !lhs.isEmpty else {
      return true
    }
    return lhs.withUnsafeBufferPointer { lhs in
      rhs.withUnsafeBufferPointer { rhs in
        unsafe lhs.baseAddress == rhs.baseAddress
      }
    }
  }
}

/// Compares cells along a pair of rows, remembering the last pair of distinct
/// attributes objects it compared by value.
///
/// Repainting a row gives its cells new attributes objects that usually equal
/// the ones they replace, and a run of cells shares one object on each side.
/// A diff that walks such a row would otherwise compare the same two styles
/// once per cell; this compares them once per run. The result is always
/// `lhs == rhs`.
package struct RasterCellRunComparator {
  private var lhsAttributes: RasterCellAttributes?
  private var rhsAttributes: RasterCellAttributes?
  private var attributesAreEqual = true
  private var hasPair = false

  package init() {}

  @inline(__always)
  package mutating func areEqual(_ lhs: RasterCell, _ rhs: RasterCell) -> Bool {
    guard lhs.hasSameSpan(as: rhs) else {
      return false
    }
    let lhsAttributes = lhs.attributes
    let rhsAttributes = rhs.attributes
    if lhsAttributes !== rhsAttributes {
      if !hasPair || self.lhsAttributes !== lhsAttributes || self.rhsAttributes !== rhsAttributes {
        attributesAreEqual = RasterCellAttributes.areEqual(lhsAttributes, rhsAttributes)
        self.lhsAttributes = lhsAttributes
        self.rhsAttributes = rhsAttributes
        hasPair = true
      }
      guard attributesAreEqual else {
        return false
      }
    }
    return lhs.character == rhs.character
  }
}

// The five reflected fields are the whole cell: the attributes object they
// are read from is immutable; exceptional counts are reflected as their values.
extension RasterCell: CompleteValueMirroring {}

extension RasterCell: CustomReflectable {
  /// Reflects the cell's public fields, not its storage, so reflection-driven
  /// output names the same five values whatever the cell shares.
  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "character": character,
        "spanWidth": spanWidth,
        "continuationLeadX": continuationLeadX as Any,
        "style": style as Any,
        "hyperlink": hyperlink as Any,
      ],
      displayStyle: .struct
    )
  }
}

/// The resolved style and hyperlink a run of raster cells shares.
///
/// Immutable, so cells on any thread can reference one instance. Two cells
/// that reference the same instance have equal attributes without a compare;
/// two instances are still compared by value, so sharing is an optimization
/// and never a correctness requirement.
package final class RasterCellAttributes: Sendable {
  package let style: ResolvedTextStyle?
  package let hyperlink: String?
  package let spanWidthOverflow: Int?
  package let continuationLeadXOverflow: Int?

  private init(
    style: ResolvedTextStyle?, hyperlink: String?,
    spanWidthOverflow: Int?, continuationLeadXOverflow: Int?
  ) {
    self.style = style
    self.hyperlink = hyperlink
    self.spanWidthOverflow = spanWidthOverflow
    self.continuationLeadXOverflow = continuationLeadXOverflow
  }

  /// Shared values, or `nil` when no out-of-line storage is needed.
  package static func make(
    style: ResolvedTextStyle?,
    hyperlink: String?,
    spanWidthOverflow: Int? = nil,
    continuationLeadXOverflow: Int? = nil
  ) -> RasterCellAttributes? {
    guard
      style != nil || hyperlink != nil || spanWidthOverflow != nil
        || continuationLeadXOverflow != nil
    else {
      return nil
    }
    return RasterCellAttributes(
      style: style, hyperlink: hyperlink,
      spanWidthOverflow: spanWidthOverflow, continuationLeadXOverflow: continuationLeadXOverflow)
  }

  /// Value equality with an identity fast path.
  @inline(__always)
  package static func areEqual(
    _ lhs: RasterCellAttributes?,
    _ rhs: RasterCellAttributes?
  ) -> Bool {
    if lhs === rhs {
      return true
    }
    guard let lhs, let rhs else {
      // `make` never produces attributes that carry nothing, so attributes
      // on one side only always differ.
      return false
    }
    return lhs.style == rhs.style && lhs.hyperlink == rhs.hyperlink
      && lhs.spanWidthOverflow == rhs.spanWidthOverflow
      && lhs.continuationLeadXOverflow == rhs.continuationLeadXOverflow
  }
}
