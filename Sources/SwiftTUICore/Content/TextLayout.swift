/// A single rendered text cluster and the number of terminal cells it occupies.
public struct TextCluster: Equatable, Sendable {
  public var character: Character
  public var cellWidth: Int
  package var runIndex: Int?

  public init(
    character: Character,
    cellWidth: Int,
    runIndex: Int? = nil
  ) {
    self.character = character
    self.cellWidth = max(0, cellWidth)
    self.runIndex = runIndex
  }
}

/// A single laid out line of terminal text.
public struct TextLayoutLine: Equatable, Sendable {
  public var clusters: [TextCluster]

  public init(clusters: [TextCluster] = []) {
    self.clusters = clusters
  }

  public var cellWidth: Int {
    clusters.reduce(0) { $0 + $1.cellWidth }
  }

  public var text: String {
    String(clusters.map(\.character))
  }
}

/// Options for wrapping and truncating text during terminal layout.
public struct TextLayoutOptions: Equatable, Hashable, Sendable {
  public var width: Int?
  public var lineLimit: Int?
  public var truncationMode: TextTruncationMode
  public var wrappingStrategy: TextWrappingStrategy

  public init(
    width: Int? = nil,
    lineLimit: Int? = nil,
    truncationMode: TextTruncationMode = .tail,
    wrappingStrategy: TextWrappingStrategy = .wordBoundary
  ) {
    self.width = width
    self.lineLimit = lineLimit
    self.truncationMode = truncationMode
    self.wrappingStrategy = wrappingStrategy
  }
}

/// Result of laying out a string into terminal cell lines.
public struct TextLayoutResult: Equatable, Sendable {
  public var lines: [TextLayoutLine]
  public var wasTruncated: Bool

  public init(
    lines: [TextLayoutLine],
    wasTruncated: Bool = false
  ) {
    self.lines = lines.isEmpty ? [.init()] : lines
    self.wasTruncated = wasTruncated
  }

  public var size: CellSize {
    CellSize(
      width: lines.map(\.cellWidth).max() ?? 0,
      height: lines.count
    )
  }
}

/// Lays out text using explicit width and truncation options.
public func layoutText(
  for content: String,
  width: Int?,
  lineLimit: Int? = nil,
  truncationMode: TextTruncationMode = .tail,
  wrappingStrategy: TextWrappingStrategy = .wordBoundary
) -> TextLayoutResult {
  layoutText(
    for: content,
    options: .init(
      width: width,
      lineLimit: lineLimit,
      truncationMode: truncationMode,
      wrappingStrategy: wrappingStrategy
    )
  )
}

/// Lays out text using a reusable options value.
public func layoutText(
  for content: String,
  options: TextLayoutOptions
) -> TextLayoutResult {
  TextLayoutCache.shared.layout(
    for: content,
    options: options
  )
}

/// Maps a single line of text directly to clusters without going through
/// the ``TextLayoutCache`` or the wrapping/truncation pipeline.  Intended
/// for preformatted text that is known to be a single, unwrapped line.
package func clusterize(_ line: String) -> [TextCluster] {
  line.map { character in
    TextCluster(
      character: character,
      cellWidth: cellWidth(of: character)
    )
  }
}

package func layoutRichText(
  for payload: RichTextPayload,
  options: TextLayoutOptions
) -> TextLayoutResult {
  TextLayoutCache.shared.layoutRich(
    for: payload,
    options: options
  )
}

func uncachedRichTextLayout(
  for payload: RichTextPayload,
  options: TextLayoutOptions
) -> TextLayoutResult {
  uncachedTextLayout(
    sourceLines: explicitClusterLines(for: payload, options: options),
    options: options
  )
}

func uncachedTextLayout(
  for content: String,
  options: TextLayoutOptions
) -> TextLayoutResult {
  uncachedTextLayout(
    sourceLines: explicitClusterLines(for: content, options: options),
    options: options
  )
}

private func uncachedTextLayout(
  sourceLines: [[TextCluster]],
  options: TextLayoutOptions
) -> TextLayoutResult {
  guard let rawLineLimit = options.lineLimit else {
    // Unbounded: wrap every source line to full depth, exactly as before.
    let wrappedLines = sourceLines.flatMap { line in
      wrapTextLine(
        line,
        width: options.width,
        wrappingStrategy: options.wrappingStrategy
      )
    }
    return TextLayoutResult(lines: wrappedLines)
  }

  let lineLimit = max(1, rawLineLimit)

  // The product is at most `lineLimit` rows, so the wrap needs at most
  // `lineLimit + 1` — one row past the limit is the entire evidence that
  // truncation is required (D71). Wrapping the whole content first and
  // discarding the tail made an O(lineLimit × width) product cost
  // O(total content).
  let rowBudget = lineLimit + 1

  // Rows stay grouped by the source line that produced them: truncation needs
  // to reach past the last visible row into the rest of *its own* logical line,
  // and only the grouping records which logical line that is.
  let indexedGroups = budgetedWrapGroups(
    sourceLines.map { line in
      line.enumerated().map { index, cluster in
        SourceIndexedCluster(sourceIndex: index, cluster: cluster)
      }
    },
    options: options,
    rowBudget: rowBudget
  )

  let wrappedLines = indexedGroups.flatMap { rows in
    rows.map { row in TextLayoutLine(clusters: row.map(\.cluster)) }
  }

  // Reaching `lineLimit + 1` emitted rows proves at least one row past the
  // limit exists; producing fewer under an unhit budget proves the wrap
  // completed. Identical to the old `allRows.count > lineLimit`.
  guard wrappedLines.count > lineLimit else {
    return TextLayoutResult(lines: wrappedLines)
  }

  var visibleLines = Array(wrappedLines.prefix(lineLimit))
  if let lastIndex = visibleLines.indices.last {
    visibleLines[lastIndex] = truncating(
      truncationInput(
        forWrappedRow: lastIndex,
        in: indexedGroups,
        sourceLines: sourceLines
      ),
      to: options.width,
      mode: options.truncationMode,
      forceIndicator: options.width != nil
    )
  }
  return TextLayoutResult(lines: visibleLines, wasTruncated: true)
}

/// Wraps source lines left to right, spending a shared row budget, and stops
/// consuming source lines once it is gone.
///
/// Every source line yields at least one row, so the budget bounds how many
/// source lines are even looked at — which is what keeps a `lineLimit(1)` over
/// a thousand-line document from wrapping a thousand lines to show one.
private func budgetedWrapGroups(
  _ sourceLines: [[SourceIndexedCluster]],
  options: TextLayoutOptions,
  rowBudget: Int
) -> [[[SourceIndexedCluster]]] {
  var groups: [[[SourceIndexedCluster]]] = []
  var remaining = rowBudget

  for line in sourceLines {
    guard remaining > 0 else {
      break
    }
    let rows = wrapTextLineClusters(
      line,
      width: options.width,
      wrappingStrategy: options.wrappingStrategy,
      rowBudget: remaining
    )
    groups.append(rows)
    remaining -= rows.count
  }

  return groups
}

private func explicitClusterLines(
  for content: String,
  options: TextLayoutOptions
) -> [[TextCluster]] {
  explicitClusterLines(
    from: [
      RichTextRun(text: content)
    ],
    options: options
  )
}

private func explicitClusterLines(
  for payload: RichTextPayload,
  options: TextLayoutOptions
) -> [[TextCluster]] {
  explicitClusterLines(from: payload.runs, options: options)
}

private func explicitClusterLines(
  from runs: [RichTextRun],
  options: TextLayoutOptions
) -> [[TextCluster]] {
  // Each source line yields at least one wrapped row, so a `lineLimit` of n can
  // never read past the (n + 1)-th source line — and clusterizing lines nobody
  // will wrap is the same O(total content) cost the row budget exists to
  // delete. Stopping here is unobservable: reaching the cap means at least
  // `lineLimit + 1` rows, which is already `wasTruncated`.
  let maximumLines = options.lineLimit.map { max(1, $0) + 1 }
  var lines: [[TextCluster]] = [[]]

  for (runIndex, run) in runs.enumerated() {
    for character in run.text {
      if character == "\n" {
        if let maximumLines, lines.count >= maximumLines {
          return lines
        }
        lines.append([])
        continue
      }

      lines[lines.count - 1].append(
        TextCluster(
          character: character,
          cellWidth: cellWidth(of: character),
          runIndex: runIndex
        )
      )
    }
  }

  return lines.isEmpty ? [[]] : lines
}
