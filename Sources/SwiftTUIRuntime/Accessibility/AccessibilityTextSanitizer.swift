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
      switch scalar.value {
      case 0x20:
        appendSpaceIfNeeded()
      case 0x21...0x7E:
        scalars.append(scalar)
        previousWasSpace = false
      case 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
        appendSpaceIfNeeded()
      default:
        scalars.append(Unicode.Scalar(0x3F)!)
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
