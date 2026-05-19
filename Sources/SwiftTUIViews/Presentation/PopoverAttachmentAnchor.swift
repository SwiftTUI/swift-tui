public import SwiftTUICore

// The popover attachment anchor.
//
// `PopoverAttachmentAnchor` names where a popover attaches relative to its
// source view — a rectangle or a point in the source's unit coordinate
// space. `attachmentRect(in:)` resolves that unit-space anchor into concrete
// terminal cells against a measured source frame.
//
// Split out of `PopoverPresentation.swift` so that file stays focused on the
// popover presentation modifiers and placement layout. The two unit→cell
// scaling helpers travel with `attachmentRect` — it is their only caller.

/// The source-relative attachment point for a popover.
public enum PopoverAttachmentAnchor: Equatable, Sendable {
  /// Attach to a rectangle inside the source view's bounds.
  case rect(UnitRect)

  /// Attach to a point inside the source view's bounds.
  case point(UnitPoint)
}

extension PopoverAttachmentAnchor {
  package func attachmentRect(
    in sourceFrame: CellRect
  ) -> CellRect {
    switch self {
    case .rect(let unitRect):
      let origin = CellPoint(
        x: sourceFrame.origin.x
          + scaledCellOffset(unitRect.origin.x, extent: sourceFrame.size.width),
        y: sourceFrame.origin.y
          + scaledCellOffset(unitRect.origin.y, extent: sourceFrame.size.height)
      )
      let size = CellSize(
        width: max(0, scaledCellExtent(unitRect.size.width, extent: sourceFrame.size.width)),
        height: max(0, scaledCellExtent(unitRect.size.height, extent: sourceFrame.size.height))
      )
      return CellRect(origin: origin, size: size)
    case .point(let unitPoint):
      return CellRect(
        origin: CellPoint(
          x: sourceFrame.origin.x + scaledCellOffset(unitPoint.x, extent: sourceFrame.size.width),
          y: sourceFrame.origin.y + scaledCellOffset(unitPoint.y, extent: sourceFrame.size.height)
        ),
        size: .zero
      )
    }
  }
}

private func scaledCellOffset(
  _ unit: Double,
  extent: Int
) -> Int {
  Int((Double(extent) * unit).rounded(.down))
}

private func scaledCellExtent(
  _ unit: Double,
  extent: Int
) -> Int {
  Int((Double(extent) * unit).rounded())
}
