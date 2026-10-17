/// Signed shape insets affect paint geometry, not the layout slot. Reject
/// unrepresentable arithmetic before a malformed extent reaches a painter.
package func shapeInsetBounds(_ bounds: CellRect, by inset: Int) -> CellRect? {
  let (twice, doubledOverflow) = inset.multipliedReportingOverflow(by: 2)
  let (x, xOverflow) = bounds.origin.x.addingReportingOverflow(inset)
  let (y, yOverflow) = bounds.origin.y.addingReportingOverflow(inset)
  let (width, widthOverflow) = bounds.size.width.subtractingReportingOverflow(twice)
  let (height, heightOverflow) = bounds.size.height.subtractingReportingOverflow(twice)
  guard !doubledOverflow, !xOverflow, !yOverflow, !widthOverflow, !heightOverflow else {
    return nil
  }
  let size = CellSize(width: max(0, width), height: max(0, height))
  guard !x.addingReportingOverflow(size.width).overflow,
    !y.addingReportingOverflow(size.height).overflow
  else { return nil }
  return CellRect(origin: .init(x: x, y: y), size: size)
}
