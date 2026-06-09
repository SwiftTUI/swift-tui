import Foundation
public import SwiftTUIRuntime

public struct AndroidHostFrameSnapshot: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var sequence: UInt64
  public var gridWidth: Int
  public var gridHeight: Int
  public var preferredGridWidth: Int?
  public var preferredGridHeight: Int?
  public var rows: [String]
  public var focusedIdentity: String?
  public var dirtyRows: [Int]
  public var requiresFullTextRepaint: Bool
  public var requiresFullGraphicsReplay: Bool

  public init(
    schemaVersion: Int = 1,
    sequence: UInt64,
    gridWidth: Int,
    gridHeight: Int,
    preferredGridWidth: Int?,
    preferredGridHeight: Int?,
    rows: [String],
    focusedIdentity: String?,
    dirtyRows: [Int],
    requiresFullTextRepaint: Bool,
    requiresFullGraphicsReplay: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.sequence = sequence
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    self.preferredGridWidth = preferredGridWidth
    self.preferredGridHeight = preferredGridHeight
    self.rows = rows
    self.focusedIdentity = focusedIdentity
    self.dirtyRows = dirtyRows
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }
}

public enum AndroidHostFrameEncoder {
  public static func snapshot(
    for frame: SemanticHostFrame
  ) -> AndroidHostFrameSnapshot {
    AndroidHostFrameSnapshot(
      sequence: frame.sequence,
      gridWidth: frame.raster.size.width,
      gridHeight: frame.raster.size.height,
      preferredGridWidth: frame.preferredLayoutSize?.width,
      preferredGridHeight: frame.preferredLayoutSize?.height,
      rows: rows(from: frame.raster),
      focusedIdentity: frame.focusedIdentity?.path,
      dirtyRows: frame.rasterDamage?.dirtyRows.sorted() ?? [],
      requiresFullTextRepaint: frame.rasterDamage?.requiresFullTextRepaint ?? true,
      requiresFullGraphicsReplay: frame.rasterDamage?.requiresFullGraphicsReplay ?? true
    )
  }

  public static func encode(
    _ frame: SemanticHostFrame
  ) throws -> [UInt8] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Array(try encoder.encode(snapshot(for: frame)))
  }

  private static func rows(
    from surface: RasterSurface
  ) -> [String] {
    surface.cells.map { row in
      String(row.map(\.character))
    }
  }
}
