package struct AccessibilityTextSanitizer: Equatable, Sendable {
  package init() {}

  package func sanitized(
    _ value: String?
  ) -> String? {
    guard let value else {
      return nil
    }

    var scalars: [Unicode.Scalar] = []
    scalars.reserveCapacity(value.unicodeScalars.count)
    var previousWasSpace = false

    func appendSpaceIfNeeded() {
      guard !previousWasSpace else {
        return
      }
      scalars.append(Unicode.Scalar(0x20)!)
      previousWasSpace = true
    }

    for scalar in value.unicodeScalars {
      if scalar.properties.isWhitespace {
        appendSpaceIfNeeded()
      } else {
        scalars.append(scalar.isTerminalControlScalar ? Unicode.Scalar(0x3F)! : scalar)
        previousWasSpace = false
      }
    }

    let trimmed = trimmingAsciiSpaces(scalars)
    guard !trimmed.isEmpty else {
      return nil
    }
    return String(String.UnicodeScalarView(trimmed))
  }

  private func trimmingAsciiSpaces(
    _ scalars: [Unicode.Scalar]
  ) -> [Unicode.Scalar] {
    var start = scalars.startIndex
    var end = scalars.endIndex

    while start < end, scalars[start].value == 0x20 {
      start = scalars.index(after: start)
    }
    while start < end {
      let previous = scalars.index(before: end)
      guard scalars[previous].value == 0x20 else {
        break
      }
      end = previous
    }

    return Array(scalars[start..<end])
  }
}
