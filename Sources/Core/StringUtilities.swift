extension String {
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
