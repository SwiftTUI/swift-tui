/// Grouped metadata for layout-relevant properties of a resolved node.
/// Used by `MeasurementCache` to compare only the fields that affect measurement,
/// avoiding unnecessary cache misses from unrelated metadata changes.
public struct NodeLayoutInfo: Equatable, Sendable {
  public var layoutBehavior: LayoutBehavior
  public var layoutMetadata: LayoutMetadata
  public var intrinsicSize: Size?

  public init(
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    intrinsicSize: Size? = nil
  ) {
    self.layoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self.intrinsicSize = intrinsicSize
  }

  /// Equivalence check for measurement caching. Uses the relaxed
  /// `isEquivalentForMeasurement` comparison for `LayoutBehavior`.
  public func isEquivalentForMeasurement(to other: Self) -> Bool {
    layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && intrinsicSize == other.intrinsicSize
  }
}

/// Grouped metadata for draw-relevant properties of a resolved node.
package struct NodeDrawInfo: Equatable, Sendable {
  package var drawMetadata: DrawMetadata
  package var drawPayload: DrawPayload

  package init(
    drawMetadata: DrawMetadata = DrawMetadata(),
    drawPayload: DrawPayload = .none
  ) {
    self.drawMetadata = drawMetadata
    self.drawPayload = drawPayload
  }
}

/// Grouped metadata for semantic properties of a resolved node.
public struct NodeSemanticInfo: Equatable, Sendable {
  public var semanticMetadata: SemanticMetadata

  public init(
    semanticMetadata: SemanticMetadata = SemanticMetadata()
  ) {
    self.semanticMetadata = semanticMetadata
  }
}

/// Grouped metadata for lifecycle properties of a resolved node.
public struct NodeLifecycleInfo: Equatable, Sendable {
  public var lifecycleMetadata: LifecycleMetadata

  public init(
    lifecycleMetadata: LifecycleMetadata = .init()
  ) {
    self.lifecycleMetadata = lifecycleMetadata
  }

  public var isEmpty: Bool {
    lifecycleMetadata.isEmpty
  }
}

// MARK: - ResolvedNode Convenience Accessors

extension ResolvedNode {
  /// Grouped layout metadata for this node.
  public var layoutInfo: NodeLayoutInfo {
    get {
      NodeLayoutInfo(
        layoutBehavior: layoutBehavior,
        layoutMetadata: layoutMetadata,
        intrinsicSize: intrinsicSize
      )
    }
    set {
      layoutBehavior = newValue.layoutBehavior
      layoutMetadata = newValue.layoutMetadata
      intrinsicSize = newValue.intrinsicSize
    }
  }

  /// Grouped draw metadata for this node.
  package var drawInfo: NodeDrawInfo {
    get {
      NodeDrawInfo(
        drawMetadata: drawMetadata,
        drawPayload: drawPayload
      )
    }
    set {
      drawMetadata = newValue.drawMetadata
      drawPayload = newValue.drawPayload
    }
  }

  /// Grouped semantic metadata for this node.
  public var semanticInfo: NodeSemanticInfo {
    get {
      NodeSemanticInfo(
        semanticMetadata: semanticMetadata
      )
    }
    set {
      semanticMetadata = newValue.semanticMetadata
    }
  }

  /// Grouped lifecycle metadata for this node.
  public var lifecycleInfo: NodeLifecycleInfo {
    get {
      NodeLifecycleInfo(
        lifecycleMetadata: lifecycleMetadata
      )
    }
    set {
      lifecycleMetadata = newValue.lifecycleMetadata
    }
  }
}

extension DrawPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    switch (self, other) {
    case (.none, .none):
      return true
    case (.text(let lhsText), .text(let rhsText)):
      return lhsText == rhsText
    case (.textFigure(let lhsPayload), .textFigure(let rhsPayload)):
      return lhsPayload == rhsPayload
    case (.text(let lhsText), .richText(let rhsPayload)):
      return lhsText == rhsPayload.visibleText
    case (.richText(let lhsPayload), .text(let rhsText)):
      return lhsPayload.visibleText == rhsText
    case (.richText(let lhsPayload), .richText(let rhsPayload)):
      return lhsPayload.visibleText == rhsPayload.visibleText
    case (.image(let lhsPayload), .image(let rhsPayload)):
      return lhsPayload.isEquivalentForMeasurement(to: rhsPayload)
    case (.shape, .shape):
      return true
    case (.rule, .rule):
      return true
    case (.canvas, .canvas):
      // ``Canvas`` is the arbitrary-drawing escape hatch.  The layout
      // engine reserves a cell frame and the rasterizer calls the user
      // closure on the surface — the drawing's content has zero
      // influence on the parent's proposed size or its own measured
      // size, exactly the way ``.shape`` and ``.rule`` work.  Treating
      // two canvases as measurement-equivalent unconditionally lets
      // the layout cache reuse them across animation tick frames.
      //
      // Without this carve-out the catch-all ``default: false`` below
      // forces every animation tick to invalidate the measurement
      // cache for the canvas leaf, and that cascades up the entire
      // ancestor spine via the recursive
      // ``ResolvedNode.isEquivalentForMeasurement`` walk — pegging the
      // run loop on any view tree that pairs an animated property
      // with a ``Canvas`` further down the same scroll content.
      return true
    case (.list(let lhsPayload), .list(let rhsPayload)):
      return lhsPayload.isEquivalentForMeasurement(to: rhsPayload)
    case (.table(let lhsPayload), .table(let rhsPayload)):
      return lhsPayload.isEquivalentForMeasurement(to: rhsPayload)
    default:
      return false
    }
  }
}

extension ImagePayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    isResizable == other.isResizable
      && scalingMode == other.scalingMode
      && resolvedAsset?.pixelSize == other.resolvedAsset?.pixelSize
      && resolvedAsset?.intrinsicCellSize == other.resolvedAsset?.intrinsicCellSize
  }
}

extension ListPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    style == other.style
      && selectedRowIndex == other.selectedRowIndex
      && showsSelectionMarker == other.showsSelectionMarker
      && items.isEquivalentForMeasurement(to: other.items)
  }
}

extension Array where Element == ListItemPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    count == other.count
      && zip(self, other).allSatisfy { lhsItem, rhsItem in
        lhsItem.isEquivalentForMeasurement(to: rhsItem)
      }
  }
}

extension ListItemPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    kind == other.kind
      && text == other.text
      && rowSeparators == other.rowSeparators
      && sectionSeparators == other.sectionSeparators
  }
}

extension TablePayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    style == other.style
      && showsHeaders == other.showsHeaders
      && columns.isEquivalentForMeasurement(to: other.columns)
      && rows.isEquivalentForMeasurement(to: other.rows)
  }
}

extension Array where Element == TableColumnPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    count == other.count
      && zip(self, other).allSatisfy { lhsColumn, rhsColumn in
        lhsColumn.isEquivalentForMeasurement(to: rhsColumn)
      }
  }
}

extension TableColumnPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    title == other.title
      && width == other.width
      && alignment == other.alignment
      && titleAlignment == other.titleAlignment
  }
}

extension Array where Element == TableRowPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    count == other.count
      && zip(self, other).allSatisfy { lhsRow, rhsRow in
        lhsRow.isEquivalentForMeasurement(to: rhsRow)
      }
  }
}

extension TableRowPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    cells.isEquivalentForMeasurement(to: other.cells)
      && rowSeparators == other.rowSeparators
  }
}

extension Array where Element == TableCellPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    count == other.count
      && zip(self, other).allSatisfy { lhsCell, rhsCell in
        lhsCell.isEquivalentForMeasurement(to: rhsCell)
      }
  }
}

extension TableCellPayload {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    text == other.text
  }
}
