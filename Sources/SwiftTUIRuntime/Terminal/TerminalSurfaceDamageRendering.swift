import SwiftTUICore

struct TerminalSurfaceDamageRenderer: Sendable {
  let capabilityProfile: TerminalCapabilityProfile

  func renderRowBatch(
    row: Int,
    currentRow: [RasterCell],
    spans: [Range<Int>]
  ) -> TerminalPresentationPlan.RowBatch? {
    let orderedSpans =
      spans
      .filter { !$0.isEmpty }
      .sorted { lhs, rhs in
        lhs.lowerBound < rhs.lowerBound
      }
    guard let firstSpan = orderedSpans.first else {
      return nil
    }

    var renderedBatch = ""
    renderedBatch.reserveCapacity(
      orderedSpans.reduce(0) { partial, span in
        partial + max(0, span.upperBound - span.lowerBound) * 3
      }
    )
    let textRenderer = TerminalCellTextRenderer(capabilityProfile: capabilityProfile)
    var state = TerminalCellTextRenderer.RenderState()
    var cursorColumn = firstSpan.lowerBound
    var spanUpdates: [TerminalPresentationPlan.SpanUpdate] = []

    for span in orderedSpans {
      if span.lowerBound > cursorColumn {
        renderedBatch += textRenderer.cursorForwardSequence(span.lowerBound - cursorColumn)
        cursorColumn = span.lowerBound
      }

      var renderedSpan = ""
      renderedSpan.reserveCapacity(max(0, span.upperBound - span.lowerBound) * 3)
      _ = textRenderer.appendRenderedCells(
        in: currentRow,
        from: span.lowerBound,
        to: span.upperBound,
        into: &renderedSpan,
        state: &state
      )
      renderedBatch += renderedSpan

      spanUpdates.append(
        .init(
          row: row,
          column: span.lowerBound,
          renderedSpan: renderedSpan,
          cellsChanged: cellsChanged(
            in: currentRow,
            from: span.lowerBound,
            to: span.upperBound
          )
        )
      )
      cursorColumn = span.upperBound
    }

    textRenderer.closeRenderState(&state, into: &renderedBatch)

    return .init(
      row: row,
      anchorColumn: firstSpan.lowerBound,
      renderedBatch: renderedBatch,
      spanUpdates: spanUpdates
    )
  }

  func diffSpans(
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int,
    limitingTo candidateRanges: [Range<Int>]? = nil
  ) -> [Range<Int>] {
    guard width > 0 else {
      return []
    }

    if let candidateRanges, !candidateRanges.isEmpty {
      var spans: [Range<Int>] = []
      for candidateRange in candidateRanges {
        appendDiffSpans(
          in: candidateRange,
          previousRow: previousRow,
          currentRow: currentRow,
          width: width,
          to: &spans
        )
      }
      return spans
    }

    var spans: [Range<Int>] = []
    appendDiffSpans(
      in: 0..<width,
      previousRow: previousRow,
      currentRow: currentRow,
      width: width,
      to: &spans
    )
    return spans
  }

  private func appendDiffSpans(
    in candidateRange: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int,
    to spans: inout [Range<Int>]
  ) {
    let lowerBound = max(0, min(width, candidateRange.lowerBound))
    let upperBound = max(lowerBound, min(width, candidateRange.upperBound))
    guard lowerBound < upperBound else {
      return
    }

    var index = lowerBound
    while index < upperBound {
      guard cell(at: index, in: previousRow) != cell(at: index, in: currentRow) else {
        index += 1
        continue
      }

      let rawStart = index
      index += 1
      while index < upperBound,
        cell(at: index, in: previousRow) != cell(at: index, in: currentRow)
      {
        index += 1
      }

      let normalized = normalizeSpan(
        rawStart..<index,
        previousRow: previousRow,
        currentRow: currentRow,
        width: width
      )

      if let last = spans.last,
        last.upperBound >= normalized.lowerBound
      {
        spans[spans.count - 1] = last.lowerBound..<max(last.upperBound, normalized.upperBound)
      } else {
        spans.append(normalized)
      }
    }
  }

  func normalizeSpan(
    _ span: Range<Int>,
    previousRow: [RasterCell],
    currentRow: [RasterCell],
    width: Int
  ) -> Range<Int> {
    guard !span.isEmpty else {
      return span
    }

    var start = max(0, min(span.lowerBound, width))
    var end = max(start, min(span.upperBound, width))

    while start > 0 {
      let candidate = min(
        leadIndexIfContinuation(at: start, in: currentRow),
        leadIndexIfContinuation(at: start, in: previousRow)
      )
      guard candidate < start else {
        break
      }
      start = candidate
    }

    while end < width {
      if cell(at: end, in: currentRow).isContinuation
        || cell(at: end, in: previousRow).isContinuation
      {
        end += 1
        continue
      }
      break
    }

    return start..<end
  }

  func leadIndexIfContinuation(
    at index: Int,
    in row: [RasterCell]
  ) -> Int {
    guard cell(at: index, in: row).isContinuation else {
      return index
    }
    return max(0, min(index, cell(at: index, in: row).continuationLeadX ?? index))
  }

  func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    Self.cell(at: index, in: row)
  }

  static func cell(
    at index: Int,
    in row: [RasterCell]
  ) -> RasterCell {
    row.indices.contains(index) ? row[index] : .empty
  }

  func cellsChanged(
    in row: [RasterCell],
    from start: Int,
    to end: Int
  ) -> Int {
    guard start < end else {
      return 0
    }

    var total = 0
    for index in start..<end {
      let cell = cell(at: index, in: row)
      guard !cell.isContinuation else {
        continue
      }
      total += max(1, cell.spanWidth)
    }
    return total
  }
}
