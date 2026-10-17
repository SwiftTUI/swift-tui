extension String {
  /// Replaces character offsets, then maps the insertion endpoint through the
  /// result's grapheme boundaries. Inserted scalars can join either neighbor.
  package func replacingCharacters(
    in range: Range<Int>, with replacement: String
  ) -> (text: String, caret: Int) {
    let count = self.count
    let lower = index(startIndex, offsetBy: max(0, min(count, range.lowerBound)))
    let upper = index(startIndex, offsetBy: max(0, min(count, range.upperBound)))
    let insertionEnd = self[..<lower].utf8.count + replacement.utf8.count
    var copy = self
    copy.replaceSubrange(lower..<upper, with: replacement)
    var byteOffset = 0
    var caret = 0
    for character in copy {
      guard byteOffset < insertionEnd else { break }
      byteOffset += character.utf8.count
      caret += 1
    }
    return (copy, caret)
  }

  package func firstLiteralRange(
    of literal: String
  ) -> Range<String.Index>? {
    guard !literal.isEmpty else {
      return startIndex..<startIndex
    }

    var searchStart = startIndex
    while searchStart < endIndex {
      var candidateIndex = searchStart
      var literalIndex = literal.startIndex

      while literalIndex < literal.endIndex,
        candidateIndex < endIndex,
        self[candidateIndex] == literal[literalIndex]
      {
        candidateIndex = index(after: candidateIndex)
        literalIndex = literal.index(after: literalIndex)
      }

      if literalIndex == literal.endIndex {
        return searchStart..<candidateIndex
      }

      searchStart = index(after: searchStart)
    }

    return nil
  }

  package func trimmedUnicodeWhitespace() -> String {
    let scalars = unicodeScalars
    var start = scalars.startIndex
    var end = scalars.endIndex

    while start < end, scalars[start].properties.isWhitespace {
      start = scalars.index(after: start)
    }

    while end > start {
      let beforeEnd = scalars.index(before: end)
      guard scalars[beforeEnd].properties.isWhitespace else {
        break
      }
      end = beforeEnd
    }

    return String(scalars[start..<end])
  }
}
