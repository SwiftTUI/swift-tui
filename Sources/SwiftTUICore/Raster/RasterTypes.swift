/// A contiguous run of cells that share the same resolved text style.
public struct RasterStyleRun: Equatable, Sendable {
  public var x: Int
  public var y: Int
  public var length: Int
  public var style: ResolvedTextStyle

  public init(
    x: Int,
    y: Int,
    length: Int,
    style: ResolvedTextStyle
  ) {
    self.x = x
    self.y = y
    self.length = length
    self.style = style
  }

  public init(
    x: Int,
    y: Int,
    length: Int,
    style: TextStyle
  ) {
    self.init(
      x: x,
      y: y,
      length: length,
      style: ResolvedTextStyle(style)
    )
  }
}

package struct RasterSurfaceFragment: Equatable, Sendable {
  package var bounds: CellRect
  package var cells: [[RasterCell]]

  package init(
    bounds: CellRect,
    cells: [[RasterCell]]
  ) {
    self.bounds = bounds
    self.cells = cells
  }
}

package struct RasterPresentationLayer: Equatable, Sendable {
  package var order: Int
  package var bounds: CellRect
  package var content: RasterPresentationLayerContent
  package var effects: [DrawEffect]

  package init(
    order: Int,
    bounds: CellRect,
    content: RasterPresentationLayerContent,
    effects: [DrawEffect] = []
  ) {
    self.order = order
    self.bounds = bounds
    self.content = content
    self.effects = effects
  }
}

package enum RasterPresentationLayerContent: Equatable, Sendable {
  case cells(RasterSurfaceFragment)
  case image(RasterImageAttachment)
}

/// A 2D grid of terminal cells produced by rasterization.
///
/// Raster owns the final cell grid, style runs as cell styles, attachments,
/// image attachments, and raster metadata. It carries no layout or semantic
/// authority: presentation damage and drawn-identity diagnostics are retained
/// beside the surface, not read back as pipeline truth.
public struct RasterSurface: Equatable, Sendable {
  public var size: CellSize
  public var cells: [[RasterCell]]
  public var attachments: [String]
  public var imageAttachments: [RasterImageAttachment]
  public var metadata: [String: String]
  package var presentationLayers: [RasterPresentationLayer]

  public init(
    size: CellSize = .zero,
    cells: [[RasterCell]] = [],
    attachments: [String] = [],
    imageAttachments: [RasterImageAttachment] = [],
    metadata: [String: String] = [:]
  ) {
    self.size = size
    self.cells = cells
    self.attachments = attachments
    self.imageAttachments = imageAttachments
    self.metadata = metadata
    self.presentationLayers = []
  }

  package init(
    size: CellSize = .zero,
    cells: [[RasterCell]] = [],
    attachments: [String] = [],
    imageAttachments: [RasterImageAttachment] = [],
    metadata: [String: String] = [:],
    presentationLayers: [RasterPresentationLayer] = []
  ) {
    self.size = size
    self.cells = cells
    self.attachments = attachments
    self.imageAttachments = imageAttachments
    self.metadata = metadata
    self.presentationLayers = presentationLayers
  }

  public init(
    size: CellSize = .zero,
    lines: [String],
    styleRuns: [RasterStyleRun] = [],
    attachments: [String] = [],
    imageAttachments: [RasterImageAttachment] = [],
    metadata: [String: String] = [:]
  ) {
    self.size = size
    self.cells = Self.makeCells(size: size, lines: lines, styleRuns: styleRuns)
    self.attachments = attachments
    self.imageAttachments = imageAttachments
    self.metadata = metadata
    self.presentationLayers = []
  }

  package init(
    size: CellSize = .zero,
    lines: [String],
    styleRuns: [RasterStyleRun] = [],
    attachments: [String] = [],
    imageAttachments: [RasterImageAttachment] = [],
    metadata: [String: String] = [:],
    presentationLayers: [RasterPresentationLayer] = []
  ) {
    self.size = size
    self.cells = Self.makeCells(size: size, lines: lines, styleRuns: styleRuns)
    self.attachments = attachments
    self.imageAttachments = imageAttachments
    self.metadata = metadata
    self.presentationLayers = presentationLayers
  }

  public static func == (lhs: RasterSurface, rhs: RasterSurface) -> Bool {
    lhs.size == rhs.size
      && lhs.cells == rhs.cells
      && lhs.attachments == rhs.attachments
      && lhs.imageAttachments == rhs.imageAttachments
      && lhs.metadata == rhs.metadata
  }

  public var lines: [String] {
    Self.trimmedLines(from: cells)
  }

  public var styleRuns: [RasterStyleRun] {
    Self.styleRuns(from: cells)
  }

  private static func makeCells(
    size: CellSize,
    lines: [String],
    styleRuns: [RasterStyleRun]
  ) -> [[RasterCell]] {
    let height = max(size.height, lines.count)
    let width = max(
      size.width,
      lines.map { layoutText(for: $0, width: nil).size.width }.max() ?? 0
    )
    guard width > 0, height > 0 else {
      return []
    }

    var cells = Array(
      repeating: Array(repeating: RasterCell.empty, count: width),
      count: height
    )

    for (y, line) in lines.enumerated() where y < height {
      let clusters = layoutText(for: line, width: nil).lines.first?.clusters ?? []
      var x = 0
      for cluster in clusters where x < width {
        let style = styleRuns.first {
          $0.y == y && x >= $0.x && x < $0.x + $0.length
        }?.style
        cells[y][x] = RasterCell(
          character: cluster.character,
          spanWidth: max(1, cluster.cellWidth),
          style: style,
          hyperlink: nil
        )
        if cluster.cellWidth > 1 {
          for offset in 1..<cluster.cellWidth where x + offset < width {
            cells[y][x + offset] = RasterCell(
              character: " ",
              spanWidth: 0,
              continuationLeadX: x,
              style: style,
              hyperlink: nil
            )
          }
        }
        x += cluster.cellWidth
      }
    }

    for run in styleRuns {
      guard run.y >= 0, run.y < cells.count else {
        continue
      }
      let endX = min(cells[run.y].count, run.x + run.length)
      guard run.x >= 0, run.x < endX else {
        continue
      }
      for x in run.x..<endX where cells[run.y][x].style == nil {
        cells[run.y][x].style = run.style
      }
    }

    return cells
  }

  private static func trimmedLines(
    from rows: [[RasterCell]]
  ) -> [String] {
    rows.map { row in
      var end = row.count
      while end > 0,
        row[end - 1].character == " ",
        !row[end - 1].isContinuation,
        row[end - 1].style == nil
      {
        end -= 1
      }

      var characters: [Character] = []
      for cell in row[..<end] where !cell.isContinuation {
        characters.append(cell.character)
      }
      return String(characters)
    }
  }

  private static func styleRuns(
    from rows: [[RasterCell]]
  ) -> [RasterStyleRun] {
    var result: [RasterStyleRun] = []

    for (y, row) in rows.enumerated() {
      var x = 0
      while x < row.count {
        guard let style = row[x].style else {
          x += 1
          continue
        }

        let startX = x
        var endX = x + 1
        while endX < row.count, row[endX].style == style {
          endX += 1
        }

        result.append(.init(x: startX, y: y, length: endX - startX, style: style))
        x = endX
      }
    }

    return result
  }
}
