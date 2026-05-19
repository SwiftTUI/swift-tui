import SwiftTUICore

/// Renders a raster surface into terminal text for a specific capability
/// profile.
///
/// This is the terminal presentation boundary. It adapts glyphs, style, color,
/// and hyperlink support for the selected profile, and sanitizes authored text
/// and OSC 8 link destinations so raster content cannot inject terminal control
/// sequences into the output stream.
public struct TerminalSurfaceRenderer {
  public let capabilityProfile: TerminalCapabilityProfile

  /// Creates a renderer for the supplied capability profile.
  public init(
    capabilityProfile: TerminalCapabilityProfile
  ) {
    self.capabilityProfile = capabilityProfile
  }

  /// Renders a full raster surface into terminal text.
  public func render(_ surface: RasterSurface) -> String {
    let rowStrings = surface.cells.map { row in
      renderRow(row)
    }
    // Pre-size: each row contributes its character count plus a \r\n separator.
    let estimatedSize = rowStrings.reduce(0) { $0 + $1.utf8.count + 2 }
    var result = ""
    result.reserveCapacity(estimatedSize)
    for (index, row) in rowStrings.enumerated() {
      if index > 0 {
        result += "\r\n"
      }
      result += row
    }
    return result
  }

  func renderRow(
    _ row: [RasterCell],
    width: Int? = nil,
    preservingTrailingWhitespace: Bool = false
  ) -> String {
    var end = row.count
    if !preservingTrailingWhitespace {
      while end > 0 {
        let cell = row[end - 1]
        if cell.isContinuation {
          end -= 1
          continue
        }
        if cell.character == " ", cell.style == nil {
          end -= 1
          continue
        }
        break
      }
    }

    return renderCells(
      in: row,
      from: 0,
      to: end,
      width: width
    )
  }

  func renderSpan(
    _ row: [RasterCell],
    from start: Int,
    to end: Int
  ) -> String {
    guard start < end else {
      return ""
    }
    return renderCells(
      in: row,
      from: max(0, start),
      to: max(start, end),
      width: end - start,
      preservingTrailingWhitespace: true
    )
  }
}

extension TerminalSurfaceRenderer {
  private var damageRenderer: TerminalSurfaceDamageRenderer {
    TerminalSurfaceDamageRenderer(capabilityProfile: capabilityProfile)
  }

  private func renderCells(
    in row: [RasterCell],
    from start: Int,
    to end: Int,
    width: Int? = nil,
    preservingTrailingWhitespace: Bool = false
  ) -> String {
    if !preservingTrailingWhitespace {
      var trimmedEnd = max(start, min(end, row.count))
      while trimmedEnd > start {
        let cell = TerminalSurfaceDamageRenderer.cell(at: trimmedEnd - 1, in: row)
        if cell.isContinuation {
          trimmedEnd -= 1
          continue
        }
        if cell.character == " ", cell.style == nil {
          trimmedEnd -= 1
          continue
        }
        break
      }
      return renderCells(
        in: row,
        from: start,
        to: trimmedEnd,
        width: width,
        preservingTrailingWhitespace: true
      )
    }

    // Reserve capacity: ~2 bytes per cell for characters, plus ~16 bytes
    // per style transition for escape sequences.  Overestimates slightly
    // but avoids repeated String reallocations.
    let cellCount = max(0, end - start)
    var result = ""
    result.reserveCapacity(cellCount * 3)
    let textRenderer = TerminalCellTextRenderer(capabilityProfile: capabilityProfile)
    var state = TerminalCellTextRenderer.RenderState()
    let renderedWidth = textRenderer.appendRenderedCells(
      in: row,
      from: start,
      to: max(start, end),
      into: &result,
      state: &state
    )
    textRenderer.closeRenderState(&state, into: &result)

    if let width {
      result += String(repeating: " ", count: max(0, width - renderedWidth))
    }

    return result
  }

  func renderRowBatch(
    row: Int,
    currentRow: [RasterCell],
    spans: [Range<Int>]
  ) -> TerminalPresentationPlan.RowBatch? {
    damageRenderer.renderRowBatch(
      row: row,
      currentRow: currentRow,
      spans: spans
    )
  }

  func diffSpans(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int,
    limitingTo candidateRanges: [Range<Int>]? = nil
  ) -> [Range<Int>] {
    damageRenderer.diffSpans(
      previousRow: previousRow,
      currentRow: currentRow,
      width: width,
      limitingTo: candidateRanges
    )
  }

  func normalizeSpan(
    _ span: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> Range<Int> {
    damageRenderer.normalizeSpan(
      span,
      previousRow: previousRow,
      currentRow: currentRow,
      width: width
    )
  }

  func leadIndexIfContinuation(
    at index: Int,
    in row: [RasterCell]
  ) -> Int {
    damageRenderer.leadIndexIfContinuation(at: index, in: row)
  }

  func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    damageRenderer.cell(at: index, in: row)
  }

  func cellsChanged(
    in row: [RasterCell],
    from start: Int,
    to end: Int
  ) -> Int {
    damageRenderer.cellsChanged(in: row, from: start, to: end)
  }
}
