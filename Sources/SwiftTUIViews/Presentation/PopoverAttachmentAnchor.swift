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
  package func attachmentRect(in sourceFrame: CellRect) -> CellRect {
    let unitOrigin: UnitPoint
    let unitSize: UnitSize
    switch self {
    case .rect(let rect):
      unitOrigin = rect.origin
      unitSize = rect.size
    case .point(let point):
      unitOrigin = point
      unitSize = .zero
    }
    let x = scaledCellCoordinate(
      unitOrigin.x, origin: sourceFrame.origin.x,
      extent: sourceFrame.size.width)
    let y = scaledCellCoordinate(
      unitOrigin.y, origin: sourceFrame.origin.y,
      extent: sourceFrame.size.height)
    let width = scaledCellExtent(unitSize.width, origin: x, extent: sourceFrame.size.width)
    let height = scaledCellExtent(unitSize.height, origin: y, extent: sourceFrame.size.height)
    return CellRect(origin: .init(x: x, y: y), size: .init(width: width, height: height))
  }
}

// Preserve representable authored overshoot. When unit scaling or coordinate
// addition overflows, use the nearest representable edge of the source.
private func scaledCellCoordinate(_ unit: Double, origin: Int, extent: Int) -> Int {
  if let offset = Int(exactly: (Double(extent) * unit).rounded(.down)) {
    let result = origin.addingReportingOverflow(offset)
    if !result.overflow { return result.partialValue }
  }
  guard unit > 0 else { return origin }
  let edge = origin.addingReportingOverflow(max(0, extent))
  return edge.overflow ? Int.max : edge.partialValue
}

private func scaledCellExtent(_ unit: Double, origin: Int, extent: Int) -> Int {
  let scaled =
    Int(exactly: (Double(extent) * unit).rounded())
    ?? (unit > 0 ? max(0, extent) : 0)
  let positive = max(0, scaled)
  // CellRect.maxX/maxY must remain representable too.
  return origin > 0 ? min(positive, Int.max - origin) : positive
}
