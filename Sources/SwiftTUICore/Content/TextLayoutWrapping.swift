func wrapTextLine(
  _ line: [TextCluster],
  width: Int?,
  wrappingStrategy: TextWrappingStrategy
) -> [TextLayoutLine] {
  guard let width else {
    return [TextLayoutLine(clusters: line)]
  }

  guard width > 0 else {
    return [.init()]
  }

  guard !line.isEmpty else {
    return [.init()]
  }

  switch wrappingStrategy {
  case .wordBoundary:
    return wrapTextLineOnWordBoundaries(
      line,
      width: width
    )
  }
}

private struct TextWrapRun: Sendable {
  enum Kind: Sendable {
    case whitespace
    case token(isWordLike: Bool)
  }

  var kind: Kind
  var clusters: [TextCluster]

  var cellWidth: Int {
    clusters.reduce(0) { $0 + $1.cellWidth }
  }
}

private func wrapTextLineOnWordBoundaries(
  _ clusters: [TextCluster],
  width: Int
) -> [TextLayoutLine] {
  let runs = textWrapRuns(in: clusters)
  var result: [TextLayoutLine] = []
  var currentClusters: [TextCluster] = []
  var currentWidth = 0
  var pendingSeparator: [TextCluster]?
  var isAtSourceLineStart = true

  func flushCurrentLine() {
    result.append(TextLayoutLine(clusters: currentClusters))
    currentClusters = []
    currentWidth = 0
  }

  func appendClusters(_ clusters: [TextCluster]) {
    for cluster in clusters {
      let clusterWidth = cluster.cellWidth

      if currentClusters.isEmpty {
        currentClusters.append(cluster)
        currentWidth = clusterWidth
        if currentWidth >= width {
          flushCurrentLine()
        }
        continue
      }

      if currentWidth + clusterWidth > width {
        flushCurrentLine()
        currentClusters.append(cluster)
        currentWidth = clusterWidth
        if currentWidth >= width {
          flushCurrentLine()
        }
        continue
      }

      currentClusters.append(cluster)
      currentWidth += clusterWidth
    }
  }

  func adoptWrappedLines(_ lines: [TextLayoutLine]) {
    guard !lines.isEmpty else {
      return
    }

    if !currentClusters.isEmpty {
      flushCurrentLine()
    }

    for line in lines.dropLast() {
      result.append(line)
    }

    let lastLine = lines.last!
    currentClusters = lastLine.clusters
    currentWidth = lastLine.cellWidth
    if currentWidth >= width {
      flushCurrentLine()
    }
  }

  func appendTokenRun(
    _ clusters: [TextCluster],
    isWordLike: Bool
  ) {
    let tokenWidth = clusters.reduce(0) { $0 + $1.cellWidth }

    if currentWidth + tokenWidth <= width {
      appendClusters(clusters)
      return
    }

    if tokenWidth <= width {
      if !currentClusters.isEmpty {
        flushCurrentLine()
      }
      appendClusters(clusters)
      return
    }

    if !currentClusters.isEmpty, currentClusters.last.map(isWhitespaceCluster) == true {
      flushCurrentLine()
    }

    if isWordLike {
      adoptWrappedLines(
        wrapWordLikeClusters(clusters, width: width)
      )
      return
    }

    appendClusters(clusters)
  }

  for run in runs {
    switch run.kind {
    case .whitespace:
      if isAtSourceLineStart {
        appendClusters(run.clusters)
      } else {
        pendingSeparator = run.clusters
      }
    case .token(let isWordLike):
      if let separatorClusters = pendingSeparator {
        let separatorWidth = separatorClusters.reduce(0) { $0 + $1.cellWidth }

        if !currentClusters.isEmpty,
          currentWidth + separatorWidth + run.cellWidth <= width
        {
          appendClusters(separatorClusters)
        } else if !currentClusters.isEmpty {
          flushCurrentLine()
        }
        pendingSeparator = nil
      }

      appendTokenRun(run.clusters, isWordLike: isWordLike)
      isAtSourceLineStart = false
    }
  }

  if let pendingSeparator {
    appendClusters(pendingSeparator)
  }

  if !currentClusters.isEmpty || result.isEmpty {
    flushCurrentLine()
  }

  return result
}

private func textWrapRuns(in clusters: [TextCluster]) -> [TextWrapRun] {
  guard let firstCluster = clusters.first else {
    return []
  }

  var result: [TextWrapRun] = []
  var currentClusters: [TextCluster] = [firstCluster]
  var currentIsWhitespace = isWhitespaceCluster(firstCluster)

  func flushCurrentRun() {
    guard !currentClusters.isEmpty else {
      return
    }

    result.append(
      TextWrapRun(
        kind: currentIsWhitespace
          ? .whitespace : .token(isWordLike: isWordLikeToken(currentClusters)),
        clusters: currentClusters
      )
    )
    currentClusters = []
  }

  for cluster in clusters.dropFirst() {
    let isWhitespace = isWhitespaceCluster(cluster)
    if isWhitespace == currentIsWhitespace {
      currentClusters.append(cluster)
      continue
    }

    flushCurrentRun()
    currentClusters = [cluster]
    currentIsWhitespace = isWhitespace
  }

  flushCurrentRun()
  return result
}

private func wrapWordLikeClusters(
  _ clusters: [TextCluster],
  width: Int
) -> [TextLayoutLine] {
  guard width >= 3 else {
    return clusterWrappedLines(for: clusters, width: width)
  }

  let continuationMarker = TextCluster(character: "–", cellWidth: 1)
  let firstLineContentWidth = width - continuationMarker.cellWidth
  let middleLineContentWidth = width - (continuationMarker.cellWidth * 2)

  guard firstLineContentWidth > 0, middleLineContentWidth > 0 else {
    return clusterWrappedLines(for: clusters, width: width)
  }

  var remaining = clusters[...]
  var remainingCellWidth = sliceCellWidth(remaining)
  var lines: [TextLayoutLine] = []

  while !remaining.isEmpty {
    if lines.isEmpty {
      let content = prefixByCellWidth(remaining, maxWidth: firstLineContentWidth)
      let contentCellWidth = sliceCellWidth(content[...])
      remaining = remaining.dropFirst(content.count)
      remainingCellWidth -= contentCellWidth
      guard !remaining.isEmpty else {
        lines.append(.init(clusters: content))
        break
      }
      lines.append(
        .init(clusters: content + [continuationMarker])
      )
      continue
    }

    if remainingCellWidth + continuationMarker.cellWidth <= width {
      lines.append(
        .init(clusters: [continuationMarker] + Array(remaining))
      )
      remaining = []
      remainingCellWidth = 0
      continue
    }

    let content = prefixByCellWidth(remaining, maxWidth: middleLineContentWidth)
    let contentCellWidth = sliceCellWidth(content[...])
    remaining = remaining.dropFirst(content.count)
    remainingCellWidth -= contentCellWidth
    guard !content.isEmpty else {
      return clusterWrappedLines(for: clusters, width: width)
    }
    lines.append(
      .init(clusters: [continuationMarker] + content + [continuationMarker])
    )
  }

  return lines
}

func wrapWordLikeClustersForTesting(
  _ clusters: [TextCluster],
  width: Int
) -> [TextLayoutLine] {
  wrapWordLikeClusters(clusters, width: width)
}

private func prefixByCellWidth(
  _ clusters: ArraySlice<TextCluster>,
  maxWidth: Int
) -> [TextCluster] {
  guard maxWidth > 0 else {
    return []
  }

  var result: [TextCluster] = []
  var usedWidth = 0

  for cluster in clusters {
    guard usedWidth + cluster.cellWidth <= maxWidth else {
      break
    }
    result.append(cluster)
    usedWidth += cluster.cellWidth
  }

  return result
}

private func sliceCellWidth(
  _ clusters: ArraySlice<TextCluster>
) -> Int {
  clusters.reduce(0) { $0 + $1.cellWidth }
}

private func clusterWrappedLines(
  for clusters: [TextCluster],
  width: Int
) -> [TextLayoutLine] {
  var result: [TextLayoutLine] = []
  var currentClusters: [TextCluster] = []
  var currentWidth = 0

  func flushCurrentLine() {
    result.append(TextLayoutLine(clusters: currentClusters))
    currentClusters = []
    currentWidth = 0
  }

  for cluster in clusters {
    let clusterWidth = cluster.cellWidth

    if currentClusters.isEmpty {
      currentClusters.append(cluster)
      currentWidth = clusterWidth
      if currentWidth >= width {
        flushCurrentLine()
      }
      continue
    }

    if currentWidth + clusterWidth > width {
      flushCurrentLine()
      currentClusters.append(cluster)
      currentWidth = clusterWidth
      if currentWidth >= width {
        flushCurrentLine()
      }
      continue
    }

    currentClusters.append(cluster)
    currentWidth += clusterWidth
  }

  if !currentClusters.isEmpty || result.isEmpty {
    flushCurrentLine()
  }

  return result
}

private func isWhitespaceCluster(_ cluster: TextCluster) -> Bool {
  cluster.character.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
}

private func isWordLikeToken(_ clusters: [TextCluster]) -> Bool {
  guard !clusters.isEmpty else {
    return false
  }

  var containsNonApostrophe = false
  for cluster in clusters {
    guard cluster.cellWidth > 0 else {
      return false
    }

    let character = cluster.character
    if character == "'" || character == "’" {
      continue
    }

    let scalars = Array(character.unicodeScalars)
    guard !scalars.isEmpty else {
      return false
    }

    for scalar in scalars {
      guard !scalar.properties.isWhitespace, isWordLikeScalar(scalar) else {
        return false
      }
    }

    containsNonApostrophe = true
  }

  return containsNonApostrophe
}

private func isWordLikeScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .uppercaseLetter,
    .lowercaseLetter,
    .titlecaseLetter,
    .modifierLetter,
    .otherLetter,
    .decimalNumber,
    .letterNumber,
    .otherNumber,
    .nonspacingMark,
    .spacingMark,
    .enclosingMark:
    return true
  default:
    return false
  }
}
