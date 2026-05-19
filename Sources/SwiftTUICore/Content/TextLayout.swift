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
  uncachedTextLayout(
    sourceLines: explicitClusterLines(for: payload),
    options: options
  )
}

func uncachedTextLayout(
  for content: String,
  options: TextLayoutOptions
) -> TextLayoutResult {
  uncachedTextLayout(
    sourceLines: explicitClusterLines(for: content),
    options: options
  )
}

private func uncachedTextLayout(
  sourceLines: [[TextCluster]],
  options: TextLayoutOptions
) -> TextLayoutResult {
  let wrappedLines = sourceLines.flatMap { line in
    wrapTextLine(
      line,
      width: options.width,
      wrappingStrategy: options.wrappingStrategy
    )
  }

  guard let rawLineLimit = options.lineLimit else {
    return TextLayoutResult(lines: wrappedLines)
  }

  let lineLimit = max(1, rawLineLimit)
  guard wrappedLines.count > lineLimit else {
    return TextLayoutResult(lines: wrappedLines)
  }

  var visibleLines = Array(wrappedLines.prefix(lineLimit))
  if let lastIndex = visibleLines.indices.last {
    visibleLines[lastIndex] = truncating(
      visibleLines[lastIndex],
      to: options.width,
      mode: options.truncationMode,
      forceIndicator: options.width != nil
    )
  }
  return TextLayoutResult(lines: visibleLines, wasTruncated: true)
}

private func explicitClusterLines(
  for content: String
) -> [[TextCluster]] {
  explicitClusterLines(
    from: [
      RichTextRun(text: content)
    ]
  )
}

private func explicitClusterLines(
  for payload: RichTextPayload
) -> [[TextCluster]] {
  explicitClusterLines(from: payload.runs)
}

private func explicitClusterLines(
  from runs: [RichTextRun]
) -> [[TextCluster]] {
  var lines: [[TextCluster]] = [[]]

  for (runIndex, run) in runs.enumerated() {
    for character in run.text {
      if character == "\n" {
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
