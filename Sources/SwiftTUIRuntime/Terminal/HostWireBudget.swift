import SwiftTUICore

/// Fixed host-wire allocation limits. Native terminal grids are independent.
package enum HostWireBudget {
  package static let recordBytes = 4 * 1024 * 1024
  package static let gridDimension = 1024
  package static let gridCells = 65536
  package static let images = 1024
  package static let metadataEntries = 65536
  package static let cellTextBytes = 256
  package static let styleBytes = 1024
  package static let rasterDimension = 8192
  package static let rasterPixels = 16 * 1024 * 1024

  package enum Exceeded: Error { case limit }

  package static let rejectionRecord =
    "\u{001E}runtimeIssue:{\"severity\":\"error\",\"code\":\"surface.budgetExceeded\","
    + "\"message\":\"Host wire allocation budget exceeded\","
    + "\"description\":\"The last valid frame is retained; the next admitted frame is a keyframe.\"}\n"

  package static func admits(_ size: CellSize) -> Bool {
    size.width >= 0 && size.height >= 0
      && size.width <= gridDimension && size.height <= gridDimension
      && size.width * size.height <= gridCells
  }

  package static func initialSize(_ size: CellSize) -> CellSize {
    admits(size) ? size : CellSize(width: 80, height: 24)
  }

  /// Renderer damage can name an old grid or contain duplicate rows after
  /// public mutation. Canonicalize only that exceptional case, with storage
  /// bounded by the current grid rather than by the incoming range count.
  package static func clippedDamage(_ damage: PresentationDamage?, in size: CellSize)
    -> PresentationDamage?
  {
    guard let damage, admits(size) else { return nil }
    var seen: Set<Int> = []
    if damage.textRows.count <= size.height
      && damage.textRows.allSatisfy({ row in
        row.row >= 0 && row.row < size.height && seen.insert(row.row).inserted
          && row.columnRanges.count <= size.width
          && row.columnRanges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= size.width }
      })
    {
      return damage
    }
    var columnsByRow: [Int: [Bool]] = [:]
    for row in damage.textRows where row.row >= 0 && row.row < size.height {
      if columnsByRow[row.row] == nil {
        columnsByRow[row.row] = Array(repeating: false, count: size.width)
      }
      if row.columnRanges.isEmpty {
        columnsByRow[row.row] = Array(repeating: true, count: size.width)
      } else {
        for range in row.columnRanges {
          let lower = max(0, min(size.width, range.lowerBound))
          let upper = max(lower, min(size.width, range.upperBound))
          for column in lower..<upper { columnsByRow[row.row]?[column] = true }
        }
      }
    }
    let rows = columnsByRow.keys.sorted().compactMap { y -> PresentationDamage.TextRow? in
      guard let columns = columnsByRow[y] else { return nil }
      var ranges: [Range<Int>] = []
      var start: Int?
      for x in 0...size.width {
        if x < size.width && columns[x] {
          if start == nil { start = x }
        } else if let lower = start {
          ranges.append(lower..<x)
          start = nil
        }
      }
      guard !ranges.isEmpty else { return nil }
      return PresentationDamage.TextRow(row: y, columnRanges: ranges)
    }
    return PresentationDamage(
      textRows: rows, graphicsInvalidation: damage.graphicsInvalidation,
      requiresFullTextRepaint: damage.requiresFullTextRepaint,
      requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
    )
  }

  package static func validate(_ model: HostWireFrameModel) throws {
    guard admits(model.gridSize), model.surface.cells.count <= model.gridSize.height,
      model.imageAttachments.count <= images,
      model.accessibilityNodes.count <= metadataEntries,
      model.accessibilityAnnouncements.count <= metadataEntries,
      model.scrollRegions.count <= metadataEntries
    else { throw Exceeded.limit }
    if let revision = model.geometryRevision, revision > HostGeometryRequest.maximumRevision {
      throw Exceeded.limit
    }
    if let preferred = model.preferredLayoutSize, !admits(preferred) {
      throw Exceeded.limit
    }
    var stringBytes = 0
    func charge(_ text: String?) throws {
      guard let text else { return }
      let bytes = try jsonStringBytes(text)
      guard bytes <= recordBytes - stringBytes else { throw Exceeded.limit }
      stringBytes += bytes
    }
    var links: Set<String> = []
    for row in model.surface.cells {
      guard row.count <= model.gridSize.width else { throw Exceeded.limit }
      for (x, cell) in row.enumerated() where !cell.isContinuation {
        guard String(cell.character).utf8.count <= cellTextBytes,
          max(1, cell.spanWidth) <= model.gridSize.width - x
        else { throw Exceeded.limit }
        if let link = cell.hyperlink, links.insert(link).inserted { try charge(link) }
      }
    }
    for node in model.accessibilityNodes {
      try charge(node.idPath)
      try charge(node.parentIDPath)
      try charge(node.roleToken)
      try charge(node.label)
      try charge(node.hint)
      try charge(node.liveRegionToken)
    }
    for announcement in model.accessibilityAnnouncements {
      try charge(announcement.message)
      try charge(announcement.politenessToken)
    }
    for region in model.scrollRegions { try charge(region.idPath) }
    for image in model.imageAttachments {
      if let size = image.pixelSize {
        guard size.width >= 0, size.height >= 0,
          size.width <= rasterDimension, size.height <= rasterDimension,
          size.width * size.height <= rasterPixels
        else { throw Exceeded.limit }
      }
    }
    try charge(model.focusedIdentity?.path)
    if let damage = model.damage {
      guard damage.textRows.count <= model.gridSize.height else { throw Exceeded.limit }
      for row in damage.textRows {
        guard row.row >= 0, row.row < model.gridSize.height,
          row.columnRanges.count <= model.gridSize.width,
          row.columnRanges.allSatisfy({
            $0.lowerBound >= 0 && $0.upperBound <= model.gridSize.width
          })
        else { throw Exceeded.limit }
      }
    }
  }

  /// Checks JSON escaping before constructing the escaped copy.
  package static func jsonStringBytes(_ text: String) throws -> Int {
    var count = 2
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22, 0x5C, 0x08, 0x0C, 0x0A, 0x0D, 0x09: count += 2
      case 0x00...0x1F: count += 6
      case 0...0x7F: count += 1
      case 0...0x7FF: count += 2
      case 0...0xFFFF: count += 3
      default: count += 4
      }
      guard count <= recordBytes else { throw Exceeded.limit }
    }
    return count
  }

  /// Stops before retaining a component that would exceed one record's budget.
  package static func collect(_ parts: some Sequence<String>) throws -> [String] {
    var result: [String] = []
    var bytes = 0
    for part in parts {
      let count = part.utf8.count + (result.isEmpty ? 0 : 1)
      guard count <= recordBytes - bytes else { throw Exceeded.limit }
      bytes += count
      result.append(part)
    }
    return result
  }

  package static func joined(_ parts: some Sequence<String>) throws -> String {
    try collect(parts).joined(separator: ",")
  }
}

/// Each append checks UTF-8 size before growing the encoded record.
package struct HostWireRecord {
  private var text: String
  private var count: Int
  private var exceeded = false

  package init(_ prefix: String) {
    text = prefix
    count = prefix.utf8.count
  }

  package static func += (lhs: inout Self, rhs: String) {
    guard !lhs.exceeded else { return }
    let bytes = rhs.utf8.count
    // The terminal LF is the only byte outside the record budget.
    let limit = HostWireBudget.recordBytes + (rhs.hasSuffix("\n") ? 1 : 0)
    guard bytes <= limit - lhs.count else {
      lhs.exceeded = true
      return
    }
    lhs.text += rhs
    lhs.count += bytes
  }

  package func finish() throws -> String {
    guard !exceeded else { throw HostWireBudget.Exceeded.limit }
    return text
  }
}
