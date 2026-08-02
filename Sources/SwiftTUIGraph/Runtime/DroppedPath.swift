/// One path from dropped or pasted file content.
/// It stays a raw string because the `Core` layer cannot `import Foundation`.
/// Thus, `Core` can represent paths without a dependency on `URL`.
/// Consumers convert the value to `URL` or `FilePath` in their own layer.
public struct DroppedPath: Equatable, Hashable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible,
  ExpressibleByStringLiteral
{
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    rawValue = value
  }

  public var description: String { rawValue }

  public var debugDescription: String { "DroppedPath(\(rawValue))" }

  public var isEmpty: Bool { rawValue.isEmpty }
}
