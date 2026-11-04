/// A typed identifier for a terminal window scene.
public struct WindowIdentifier: Hashable, Sendable, Codable, RawRepresentable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public typealias RawValue = String
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = normalizedWindowIdentifier(rawValue)
  }

  public init<S: StringProtocol>(_ rawValue: S) {
    self.init(rawValue: String(rawValue))
  }

  public init(stringLiteral value: StringLiteralType) {
    self.init(value)
  }

  public var description: String {
    rawValue
  }
}

private func normalizedWindowIdentifier(_ value: String) -> String {
  let trimmed = value.trimmedUnicodeWhitespace()
  guard !trimmed.isEmpty else {
    return "window"
  }

  return String(
    trimmed.map { character in
      switch character {
      case "/", " ":
        "-"
      default:
        character
      }
    }
  )
}
