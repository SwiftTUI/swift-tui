package struct TextInputLineMetric: Equatable, Sendable {
  package var lineIndex: Int
  package var lineStart: TextOffset
  package var lineEnd: TextOffset
  package var column: Int
}

package enum TextInputStringMetrics {
  package static func clampedOffset(
    _ offset: TextOffset,
    in text: String
  ) -> TextOffset {
    TextOffset(min(offset.rawValue, text.count))
  }

  package static func stringIndex(
    for offset: TextOffset,
    in text: String
  ) -> String.Index {
    let clamped = min(offset.rawValue, text.count)
    return text.index(text.startIndex, offsetBy: clamped)
  }

  package static func replacing(
    range: TextRange,
    in text: String,
    with replacement: String
  ) -> String {
    let clampedRange = range.clamped(to: TextOffset(text.count))
    let lower = stringIndex(for: clampedRange.lowerBound, in: text)
    let upper = stringIndex(for: clampedRange.upperBound, in: text)
    var copy = text
    copy.replaceSubrange(lower..<upper, with: replacement)
    return copy
  }

  package static func lineMetric(
    for offset: TextOffset,
    in text: String
  ) -> TextInputLineMetric {
    let clamped = min(offset.rawValue, text.count)
    let starts = lineStarts(in: text)
    var lineIndex = 0
    for index in starts.indices {
      if starts[index] <= clamped {
        lineIndex = index
      } else {
        break
      }
    }

    let start = starts[lineIndex]
    let end: Int
    if starts.indices.contains(lineIndex + 1) {
      end = starts[lineIndex + 1] - 1
    } else {
      end = text.count
    }
    let clampedToLine = min(max(clamped, start), end)
    return TextInputLineMetric(
      lineIndex: lineIndex,
      lineStart: TextOffset(start),
      lineEnd: TextOffset(end),
      column: clampedToLine - start
    )
  }

  package static func offset(
    lineIndex: Int,
    column: Int,
    in text: String
  ) -> TextOffset {
    let starts = lineStarts(in: text)
    guard !starts.isEmpty else {
      return TextOffset(0)
    }
    let clampedLine = min(max(0, lineIndex), starts.count - 1)
    let start = starts[clampedLine]
    let end: Int
    if starts.indices.contains(clampedLine + 1) {
      end = starts[clampedLine + 1] - 1
    } else {
      end = text.count
    }
    return TextOffset(start + min(max(0, column), end - start))
  }

  package static func lineCount(in text: String) -> Int {
    lineStarts(in: text).count
  }

  package static func wordBoundaryBefore(
    _ offset: TextOffset,
    in text: String
  ) -> TextOffset {
    let characters = Array(text)
    var index = min(offset.rawValue, characters.count)
    guard index > 0 else {
      return TextOffset(0)
    }

    index -= 1
    while index > 0 && !isWordCharacter(characters[index]) {
      index -= 1
    }
    guard isWordCharacter(characters[index]) else {
      return TextOffset(0)
    }
    while index > 0 && isWordCharacter(characters[index - 1]) {
      index -= 1
    }
    return TextOffset(index)
  }

  package static func wordBoundaryAfter(
    _ offset: TextOffset,
    in text: String
  ) -> TextOffset {
    let characters = Array(text)
    var index = min(offset.rawValue, characters.count)
    guard index < characters.count else {
      return TextOffset(characters.count)
    }

    if isWordCharacter(characters[index]) {
      while index < characters.count && isWordCharacter(characters[index]) {
        index += 1
      }
    } else {
      while index < characters.count && !isWordCharacter(characters[index]) {
        index += 1
      }
      while index < characters.count && isWordCharacter(characters[index]) {
        index += 1
      }
    }
    return TextOffset(index)
  }

  private static func lineStarts(in text: String) -> [Int] {
    var starts = [0]
    for (offset, character) in text.enumerated() where character == "\n" {
      starts.append(offset + 1)
    }
    return starts
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
  }
}
