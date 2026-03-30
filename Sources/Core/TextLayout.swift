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

package final class TextLayoutCache: @unchecked Sendable {
  private struct Key: Hashable, Sendable {
    let content: String
    let options: TextLayoutOptions
  }

  package struct Metrics: Equatable, Sendable {
    package var entries: Int
    package var lookups: Int
    package var hits: Int
    package var misses: Int
    package var stores: Int
    package var evictions: Int

    package init(
      entries: Int = 0,
      lookups: Int = 0,
      hits: Int = 0,
      misses: Int = 0,
      stores: Int = 0,
      evictions: Int = 0
    ) {
      self.entries = entries
      self.lookups = lookups
      self.hits = hits
      self.misses = misses
      self.stores = stores
      self.evictions = evictions
    }
  }

  private struct Storage {
    var entries: [Key: TextLayoutResult] = [:]
    var order: [Key] = []
    var lookups = 0
    var hits = 0
    var misses = 0
    var stores = 0
    var evictions = 0
  }

  package static let shared = TextLayoutCache()

  private let capacity: Int
  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init(capacity: Int = 256) {
    self.capacity = max(1, capacity)
  }

  package var metrics: Metrics {
    storage.withLock { storage in
      Metrics(
        entries: storage.entries.count,
        lookups: storage.lookups,
        hits: storage.hits,
        misses: storage.misses,
        stores: storage.stores,
        evictions: storage.evictions
      )
    }
  }

  package func reset() {
    storage.withLock { storage in
      storage.entries.removeAll(keepingCapacity: true)
      storage.order.removeAll(keepingCapacity: true)
      storage.lookups = 0
      storage.hits = 0
      storage.misses = 0
      storage.stores = 0
      storage.evictions = 0
    }
  }

  package func layout(
    for content: String,
    options: TextLayoutOptions
  ) -> TextLayoutResult {
    let key = Key(content: content, options: options)

    if let cached = storage.withLock({ storage -> TextLayoutResult? in
      storage.lookups += 1
      guard let cached = storage.entries[key] else {
        storage.misses += 1
        return nil
      }
      storage.hits += 1
      promote(key, in: &storage)
      return cached
    }) {
      return cached
    }

    let result = uncachedTextLayout(
      for: content,
      options: options
    )

    return storage.withLock { storage in
      if let cached = storage.entries[key] {
        storage.hits += 1
        promote(key, in: &storage)
        return cached
      }

      storage.stores += 1
      storage.entries[key] = result
      storage.order.append(key)
      evictIfNeeded(in: &storage)
      return result
    }
  }

  private func promote(
    _ key: Key,
    in storage: inout Storage
  ) {
    guard let index = storage.order.firstIndex(of: key) else {
      return
    }
    storage.order.remove(at: index)
    storage.order.append(key)
  }

  private func evictIfNeeded(
    in storage: inout Storage
  ) {
    while storage.order.count > capacity {
      let victim = storage.order.removeFirst()
      storage.entries.removeValue(forKey: victim)
      storage.evictions += 1
    }
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

  public var size: Size {
    Size(
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

package func layoutRichText(
  for payload: RichTextPayload,
  options: TextLayoutOptions
) -> TextLayoutResult {
  uncachedTextLayout(
    sourceLines: explicitClusterLines(for: payload),
    options: options
  )
}

private func uncachedTextLayout(
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

private func wrapTextLine(
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
  var lines: [TextLayoutLine] = []

  while !remaining.isEmpty {
    if lines.isEmpty {
      let content = Array(remaining.prefix(firstLineContentWidth))
      remaining = remaining.dropFirst(content.count)
      guard !remaining.isEmpty else {
        lines.append(.init(clusters: content))
        break
      }
      lines.append(
        .init(clusters: content + [continuationMarker])
      )
      continue
    }

    if remaining.count + continuationMarker.cellWidth <= width {
      lines.append(
        .init(clusters: [continuationMarker] + Array(remaining))
      )
      remaining = []
      continue
    }

    let content = Array(remaining.prefix(middleLineContentWidth))
    remaining = remaining.dropFirst(content.count)
    guard !content.isEmpty else {
      return clusterWrappedLines(for: clusters, width: width)
    }
    lines.append(
      .init(clusters: [continuationMarker] + content + [continuationMarker])
    )
  }

  return lines
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

private func truncating(
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

private func textClusters(
  in line: String,
  runIndex: Int? = nil
) -> [TextCluster] {
  line.map { character in
    TextCluster(
      character: character,
      cellWidth: cellWidth(of: character),
      runIndex: runIndex
    )
  }
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
    guard cluster.cellWidth == 1 else {
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

private func cellWidth(of character: Character) -> Int {
  let scalars = Array(character.unicodeScalars)
  guard !scalars.isEmpty else {
    return 0
  }

  let containsEmojiPresentation = scalars.contains {
    $0.properties.isEmojiPresentation
  }
  let containsEmojiCluster =
    scalars.count > 1
    && scalars.contains {
      $0.properties.isEmoji
    }
  if containsEmojiPresentation || containsEmojiCluster {
    return 2
  }

  if scalars.contains(where: isWideScalar) {
    return 2
  }

  if scalars.allSatisfy(isZeroWidthScalar) {
    return 0
  }

  return 1
}

private func isZeroWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.properties.generalCategory {
  case .nonspacingMark, .enclosingMark, .format:
    return true
  default:
    return false
  }
}

private func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x1100...0x115F,
    0x2329...0x232A,
    0x2E80...0xA4CF,
    0xAC00...0xD7A3,
    0xF900...0xFAFF,
    0xFE10...0xFE19,
    0xFE30...0xFE6F,
    0xFF00...0xFF60,
    0xFFE0...0xFFE6,
    0x1F300...0x1FAFF,
    0x20000...0x3FFFD:
    return true
  default:
    return false
  }
}
