extension Rasterizer {
  func sampledBackgroundColor(
    outside side: BorderSide,
    fromX x: Int,
    y: Int,
    cells: [[RasterCell]]
  ) -> Color? {
    let samplePoint: (x: Int, y: Int) =
      switch side {
      case .top:
        (x, y - 1)
      case .right:
        (x + 1, y)
      case .bottom:
        (x, y + 1)
      case .left:
        (x - 1, y)
      }

    return resolvedCellStyle(
      atX: samplePoint.x,
      y: samplePoint.y,
      cells: cells
    )?.backgroundColor
  }

  func resolvedCellStyle(
    atX x: Int,
    y: Int,
    cells: [[RasterCell]]
  ) -> ResolvedTextStyle? {
    guard y >= 0, y < cells.count, x >= 0, x < cells[y].count else {
      return nil
    }

    let cell = cells[y][x]
    if let leadX = cell.continuationLeadX {
      guard leadX >= 0, leadX < cells[y].count else {
        return nil
      }
      return cells[y][leadX].style
    }

    return cell.style
  }
}
