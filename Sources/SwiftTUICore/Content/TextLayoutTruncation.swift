/// The line ``truncating(_:to:mode:forceIndicator:)`` must be handed for the
/// last visible wrapped row.
///
/// Truncation reads the **logical** line, never the wrapped fragment. `.head`
/// and `.middle` slice the *trailing* clusters of whatever they are given, and
/// a wrapped fragment's trailing clusters are the continuation of the head plus
/// a synthesized `–` marker — not the string's tail. Feeding the fragment made
/// every `.middle`/`.head` render "head…continuation-of-head–"
/// (docs/reports/2026-07-27-001).
///
/// The result is the row's own leading continuation markers — which it
/// genuinely owns, they signal "this word started on the row above" — followed
/// by every source cluster from the row's first source cluster through the end
/// of its logical line. Rows past the limit are folded back in this way; later
/// logical lines are not, so a two-line `.middle` shows the tail of the line it
/// is truncating rather than the tail of the whole document.
func truncationInput(
  forWrappedRow globalRowIndex: Int,
  in wrappedGroups: [[TextLayoutLine]],
  sourceLines: [[TextCluster]],
  options: TextLayoutOptions
) -> TextLayoutLine {
  var rowIndex = globalRowIndex
  for (sourceLineIndex, rows) in wrappedGroups.enumerated() {
    if rowIndex < rows.count {
      return truncationInput(
        forRow: rows[rowIndex],
        at: rowIndex,
        of: sourceLines[sourceLineIndex],
        options: options
      )
    }
    rowIndex -= rows.count
  }
  // Unreachable for a row index drawn from the wrapped rows themselves.
  return .init()
}

private func truncationInput(
  forRow row: TextLayoutLine,
  at rowIndex: Int,
  of sourceLine: [TextCluster],
  options: TextLayoutOptions
) -> TextLayoutLine {
  // The first row starts at the head of its logical line, so the whole line is
  // the remainder and the source-index re-wrap can be skipped entirely. This is
  // the `lineLimit(1)` path, which is the overwhelmingly common one.
  guard rowIndex > 0 else {
    return TextLayoutLine(clusters: sourceLine)
  }

  let indexedRows = wrapTextLineClusters(
    sourceLine.enumerated().map { index, cluster in
      SourceIndexedCluster(sourceIndex: index, cluster: cluster)
    },
    width: options.width,
    wrappingStrategy: options.wrappingStrategy
  )
  guard rowIndex < indexedRows.count else {
    return row
  }

  var leadingMarkers: [TextCluster] = []
  for cluster in indexedRows[rowIndex] {
    guard let sourceIndex = cluster.sourceIndex else {
      leadingMarkers.append(cluster.cluster)
      continue
    }
    return TextLayoutLine(clusters: leadingMarkers + sourceLine[sourceIndex...])
  }
  return row
}

/// A source cluster paired with its index in the logical, pre-wrap line, so a
/// wrapped row can be mapped back to the point in that line where it starts.
/// Continuation markers are synthesized by wrapping and carry no source
/// position, exactly as ``TextWrappableCluster`` requires — which is what makes
/// them distinguishable from real content here.
private struct SourceIndexedCluster: TextWrappableCluster {
  var sourceIndex: Int?
  var cluster: TextCluster

  var character: Character { cluster.character }
  var cellWidth: Int { cluster.cellWidth }

  static func continuationMarker(
    character: Character,
    cellWidth: Int
  ) -> SourceIndexedCluster {
    .init(
      sourceIndex: nil,
      cluster: TextCluster(character: character, cellWidth: cellWidth)
    )
  }
}

func truncating(
  _ line: TextLayoutLine,
  to width: Int?,
  mode: TextTruncationMode,
  forceIndicator: Bool
) -> TextLayoutLine {
  guard forceIndicator, let width else {
    return line
  }

  guard width > 0 else {
    return .init()
  }

  let ellipsis = TextCluster(character: "…", cellWidth: 1)
  if width == 1 {
    return .init(clusters: [ellipsis])
  }

  let availableWidth = width - ellipsis.cellWidth
  if availableWidth <= 0 {
    return .init(clusters: [ellipsis])
  }

  switch mode {
  case .tail:
    return .init(
      clusters: fittingLeadingClusters(in: line.clusters, width: availableWidth) + [ellipsis])
  case .head:
    return .init(
      clusters: [ellipsis] + fittingTrailingClusters(in: line.clusters, width: availableWidth))
  case .middle:
    let leadingWidth = availableWidth / 2
    let trailingWidth = availableWidth - leadingWidth
    return .init(
      clusters: fittingLeadingClusters(in: line.clusters, width: leadingWidth)
        + [ellipsis]
        + fittingTrailingClusters(in: line.clusters, width: trailingWidth)
    )
  }
}

private func fittingLeadingClusters(
  in clusters: [TextCluster],
  width: Int
) -> [TextCluster] {
  guard width > 0 else {
    return []
  }

  var result: [TextCluster] = []
  var usedWidth = 0
  for cluster in clusters {
    guard usedWidth + cluster.cellWidth <= width else {
      break
    }
    result.append(cluster)
    usedWidth += cluster.cellWidth
  }
  return result
}

private func fittingTrailingClusters(
  in clusters: [TextCluster],
  width: Int
) -> [TextCluster] {
  guard width > 0 else {
    return []
  }

  var result: [TextCluster] = []
  var usedWidth = 0
  for cluster in clusters.reversed() {
    guard usedWidth + cluster.cellWidth <= width else {
      break
    }
    result.append(cluster)
    usedWidth += cluster.cellWidth
  }
  return result.reversed()
}
