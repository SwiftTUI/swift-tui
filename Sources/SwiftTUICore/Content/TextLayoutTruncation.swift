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
/// The rows here are the *same* wrap that produced the visible output — the
/// primary wrap runs over ``SourceIndexedCluster`` and the visible rows are
/// derived from it by stripping indexes. That is what makes the source mapping
/// structural rather than correlated: there is no second wrap to disagree with,
/// so neither `rowIndex` bounds nor row boundaries can diverge, and the two
/// silent fall-backs this function used to carry (D78) have no case to cover.
func truncationInput(
  forWrappedRow globalRowIndex: Int,
  in wrappedGroups: [[[SourceIndexedCluster]]],
  sourceLines: [[TextCluster]]
) -> TextLayoutLine {
  var rowIndex = globalRowIndex
  for (sourceLineIndex, rows) in wrappedGroups.enumerated() {
    if rowIndex < rows.count {
      return truncationInput(
        forRow: rows[rowIndex],
        at: rowIndex,
        of: sourceLines[sourceLineIndex]
      )
    }
    rowIndex -= rows.count
  }
  // Unreachable for a row index drawn from the wrapped rows themselves.
  return .init()
}

private func truncationInput(
  forRow row: [SourceIndexedCluster],
  at rowIndex: Int,
  of sourceLine: [TextCluster]
) -> TextLayoutLine {
  // The first row starts at the head of its logical line, so the whole line is
  // the remainder and no index lookup is needed. This is the `lineLimit(1)`
  // path, which is the overwhelmingly common one.
  guard rowIndex > 0 else {
    return TextLayoutLine(clusters: sourceLine)
  }

  var leadingMarkers: [TextCluster] = []
  for cluster in row {
    guard let sourceIndex = cluster.sourceIndex else {
      leadingMarkers.append(cluster.cluster)
      continue
    }
    return TextLayoutLine(clusters: leadingMarkers + sourceLine[sourceIndex...])
  }
  // A row of pure continuation markers owns no source position, so its markers
  // *are* its whole content. This is the loop's own accumulation, not a
  // fall-back to some other wrap's answer — the distinction that made the old
  // `return row` a silent revert to the known-bad fragment.
  return TextLayoutLine(clusters: leadingMarkers)
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
