package struct TextInputLineMetric: Equatable, Sendable {
  package var lineIndex: Int
  package var lineStart: TextOffset
  package var lineEnd: TextOffset
  package var column: Int
}

/// Which grapheme boundary a UTF-16 offset inside a grapheme snaps to.
package enum TextInputUTF16Rounding: Sendable {
  case down
  case up
}

/// The grapheme boundaries of one string as UTF-16 offsets: the explicit
/// translation between a host editor's code units and the runtime's
/// `Character` offsets. `boundaries[i]` is the UTF-16 offset before the `i`th
/// `Character`; the last element is the string's UTF-16 length.
package struct TextInputUTF16Map: Sendable {
  package let boundaries: [Int]

  package init(_ text: String) {
    var boundaries = [0]
    boundaries.reserveCapacity(text.utf16.count + 1)
    var units = 0
    for character in text {
      units += character.utf16.count
      boundaries.append(units)
    }
    self.boundaries = boundaries
  }

  /// The UTF-16 length of the string.
  package var utf16Count: Int {
    boundaries[boundaries.count - 1]
  }

  /// The `Character` offset for a UTF-16 offset. An offset inside a grapheme
  /// (between surrogates, before a combining mark, inside a joined emoji or a
  /// CR LF) snaps to that grapheme's start or end. `nil` when out of range.
  package func offset(
    utf16 offset: Int,
    rounding: TextInputUTF16Rounding
  ) -> TextOffset? {
    guard offset >= 0, offset <= utf16Count else {
      return nil
    }
    // The first boundary at or after the offset.
    var low = 0
    var high = boundaries.count - 1
    while low < high {
      let middle = (low + high) / 2
      if boundaries[middle] < offset {
        low = middle + 1
      } else {
        high = middle
      }
    }
    if boundaries[low] == offset || rounding == .up {
      return TextOffset(low)
    }
    return TextOffset(low - 1)
  }

  /// The UTF-16 offset before the `Character` at `offset`, clamped.
  package func utf16Offset(for offset: TextOffset) -> Int {
    boundaries[min(offset.rawValue, boundaries.count - 1)]
  }
}

package enum TextInputStringMetrics {
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
  ) -> (text: String, caret: TextOffset) {
    let result = text.replacingCharacters(
      in: range.lowerBound.rawValue..<range.upperBound.rawValue, with: replacement)
    return (result.text, TextOffset(result.caret))
  }

  package static func substring(
    range: TextRange,
    in text: String
  ) -> String {
    let clampedRange = range.clamped(to: TextOffset(text.count))
    let lower = stringIndex(for: clampedRange.lowerBound, in: text)
    let upper = stringIndex(for: clampedRange.upperBound, in: text)
    return String(text[lower..<upper])
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
    while index > 0 && !isWordCharacter(at: index, in: characters) {
      index -= 1
    }
    guard isWordCharacter(at: index, in: characters) else {
      return TextOffset(0)
    }
    while index > 0 && isWordCharacter(at: index - 1, in: characters) {
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

    if isWordCharacter(at: index, in: characters) {
      while index < characters.count && isWordCharacter(at: index, in: characters) {
        index += 1
      }
    } else {
      while index < characters.count && !isWordCharacter(at: index, in: characters) {
        index += 1
      }
      while index < characters.count && isWordCharacter(at: index, in: characters) {
        index += 1
      }
    }
    return TextOffset(index)
  }

  private static func lineStarts(in text: String) -> [Int] {
    var starts = [0]
    for (offset, character) in text.enumerated() where character.isNewline {
      starts.append(offset + 1)
    }
    return starts
  }

  private static func isWordCharacter(at index: Int, in characters: [Character]) -> Bool {
    let character = characters[index]
    if isWordCharacter(character) { return true }
    guard index > 0, index + 1 < characters.count else { return false }
    switch character {
    case "'", "’":
      return isWordCharacter(characters[index - 1]) && isWordCharacter(characters[index + 1])
    case ".", ",":
      return characters[index - 1].isNumber && characters[index + 1].isNumber
    default:
      return false
    }
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
  }
}
