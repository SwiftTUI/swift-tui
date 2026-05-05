public protocol ForeignSurfacePayload: Sendable {
  var grid: ForeignGrid { get }
}

public struct ForeignGrid: Sendable, Equatable {
  public var size: CellSize
  public var cells: [[RasterCell]]

  public init(size: CellSize, cells: [[RasterCell]]) {
    self.size = size
    self.cells = cells
  }

  public static let empty = ForeignGrid(size: CellSize(width: 0, height: 0), cells: [])
}
