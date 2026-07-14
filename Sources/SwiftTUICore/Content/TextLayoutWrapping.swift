/// The cluster surface the wrapping algorithm reads. `TextCluster` is the
/// rendered conformer; `TextInputLayoutMapBuilder` (SwiftTUIViews) wraps
/// source-indexed clusters through the SAME algorithm so the caret movement
/// map and the rendered rows can never disagree on wrap points (F140 — the
/// map previously re-implemented wrapping at character granularity, so
/// Up/Down and click-to-caret targeted rows the renderer never drew).
package protocol TextWrappableCluster {
  var character: Character { get }
  var cellWidth: Int { get }
  /// The marker glyph synthesized when an over-wide word-like token is split
  /// mid-word. Synthesized clusters have no source position; conformers that
  /// carry source indices must mint these index-free.
  static func continuationMarker(character: Character, cellWidth: Int) -> Self
}

extension TextCluster: TextWrappableCluster {
  package static func continuationMarker(
    character: Character,
    cellWidth: Int
  ) -> TextCluster {
    TextCluster(character: character, cellWidth: cellWidth)
  }
}

func wrapTextLine(
  _ line: [TextCluster],
  width: Int?,
  wrappingStrategy: TextWrappingStrategy
) -> [TextLayoutLine] {
  wrapTextLineClusters(
    line,
    width: width,
    wrappingStrategy: wrappingStrategy
  ).map(TextLayoutLine.init(clusters:))
}

/// The single wrapping implementation, generic over the cluster payload so
/// every consumer wraps identically. Returns the wrapped rows as cluster
/// arrays; rows may contain synthesized continuation markers, and separator
/// whitespace at a wrap point is dropped (not represented in any row).
package func wrapTextLineClusters<Cluster: TextWrappableCluster>(
  _ line: [Cluster],
  width: Int?,
  wrappingStrategy: TextWrappingStrategy
) -> [[Cluster]] {
  guard let width else {
    return [line]
  }

  guard width > 0 else {
    return [[]]
  }

  guard !line.isEmpty else {
    return [[]]
  }

  switch wrappingStrategy {
  case .wordBoundary:
    return wrapTextLineOnWordBoundaries(
      line,
      width: width
    )
  }
}

private struct TextWrapRun<Cluster: TextWrappableCluster> {
  enum Kind {
    case whitespace
    case token(isWordLike: Bool)
  }

  var kind: Kind
  var clusters: [Cluster]

  var cellWidth: Int {
    clusters.reduce(0) { $0 + $1.cellWidth }
  }
}

private func wrapTextLineOnWordBoundaries<Cluster: TextWrappableCluster>(
  _ clusters: [Cluster],
  width: Int
) -> [[Cluster]] {
  let runs = textWrapRuns(in: clusters)
  var result: [[Cluster]] = []
  var currentClusters: [Cluster] = []
  var currentWidth = 0
  var pendingSeparator: [Cluster]?
  var isAtSourceLineStart = true

  func flushCurrentLine() {
    result.append(currentClusters)
    currentClusters = []
    currentWidth = 0
  }

  func appendClusters(_ clusters: [Cluster]) {
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

  func adoptWrappedLines(_ lines: [[Cluster]]) {
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
    currentClusters = lastLine
    currentWidth = lastLine.reduce(0) { $0 + $1.cellWidth }
    if currentWidth >= width {
      flushCurrentLine()
    }
  }

  func appendTokenRun(
    _ clusters: [Cluster],
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

private func textWrapRuns<Cluster: TextWrappableCluster>(
  in clusters: [Cluster]
) -> [TextWrapRun<Cluster>] {
  guard let firstCluster = clusters.first else {
    return []
  }

  var result: [TextWrapRun<Cluster>] = []
  var currentClusters: [Cluster] = [firstCluster]
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

private func wrapWordLikeClusters<Cluster: TextWrappableCluster>(
  _ clusters: [Cluster],
  width: Int
) -> [[Cluster]] {
  guard width >= 3 else {
    return clusterWrappedLines(for: clusters, width: width)
  }

  let continuationMarker = Cluster.continuationMarker(character: "–", cellWidth: 1)
  let firstLineContentWidth = width - continuationMarker.cellWidth
  let middleLineContentWidth = width - (continuationMarker.cellWidth * 2)

  guard firstLineContentWidth > 0, middleLineContentWidth > 0 else {
    return clusterWrappedLines(for: clusters, width: width)
  }

  var remaining = clusters[...]
  var remainingCellWidth = sliceCellWidth(remaining)
  var lines: [[Cluster]] = []

  while !remaining.isEmpty {
    if lines.isEmpty {
      let content = prefixByCellWidth(remaining, maxWidth: firstLineContentWidth)
      let contentCellWidth = sliceCellWidth(content[...])
      remaining = remaining.dropFirst(content.count)
      remainingCellWidth -= contentCellWidth
      guard !remaining.isEmpty else {
        lines.append(content)
        break
      }
      lines.append(content + [continuationMarker])
      continue
    }

    if remainingCellWidth + continuationMarker.cellWidth <= width {
      lines.append([continuationMarker] + Array(remaining))
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
    lines.append([continuationMarker] + content + [continuationMarker])
  }

  return lines
}

func wrapWordLikeClustersForTesting(
  _ clusters: [TextCluster],
  width: Int
) -> [TextLayoutLine] {
  wrapWordLikeClusters(clusters, width: width).map(TextLayoutLine.init(clusters:))
}

private func prefixByCellWidth<Cluster: TextWrappableCluster>(
  _ clusters: ArraySlice<Cluster>,
  maxWidth: Int
) -> [Cluster] {
  guard maxWidth > 0 else {
    return []
  }

  var result: [Cluster] = []
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

private func sliceCellWidth<Cluster: TextWrappableCluster>(
  _ clusters: ArraySlice<Cluster>
) -> Int {
  clusters.reduce(0) { $0 + $1.cellWidth }
}

private func clusterWrappedLines<Cluster: TextWrappableCluster>(
  for clusters: [Cluster],
  width: Int
) -> [[Cluster]] {
  var result: [[Cluster]] = []
  var currentClusters: [Cluster] = []
  var currentWidth = 0

  func flushCurrentLine() {
    result.append(currentClusters)
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

private func isWhitespaceCluster<Cluster: TextWrappableCluster>(
  _ cluster: Cluster
) -> Bool {
  cluster.character.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
}

private func isWordLikeToken<Cluster: TextWrappableCluster>(
  _ clusters: [Cluster]
) -> Bool {
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
