@_spi(Testing) import SwiftTUIPrimitives

/// Grouped metadata for layout-relevant properties of a resolved node.
/// Used by `MeasurementCache` to compare only the fields that affect measurement,
/// avoiding unnecessary cache misses from unrelated metadata changes.
package struct NodeLayoutInfo: Equatable, Sendable {
  package var layoutBehavior: LayoutBehavior
  package var layoutMetadata: LayoutMetadata
  package var intrinsicSize: CellSize?

  package init(
    layoutBehavior: LayoutBehavior = .intrinsic,
    layoutMetadata: LayoutMetadata = .init(),
    intrinsicSize: CellSize? = nil
  ) {
    self.layoutBehavior = layoutBehavior
    self.layoutMetadata = layoutMetadata
    self.intrinsicSize = intrinsicSize
  }

  /// Equivalence check for measurement caching. Uses the relaxed
  /// `isEquivalentForMeasurement` comparison for `LayoutBehavior`.
  package func isEquivalentForMeasurement(to other: Self) -> Bool {
    layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && intrinsicSize == other.intrinsicSize
  }
}

extension ResolvedNode {
  /// Grouped layout metadata for this node.
  package var layoutInfo: NodeLayoutInfo {
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
}
