/// A single path that arrived via a drop or paste of file-shaped content. Kept
/// as a raw string so the `Core` layer — which may not `import Foundation` — can
/// represent paths without pulling in `URL`. Consumers convert to `URL` or
/// `FilePath` at their own layer.
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
