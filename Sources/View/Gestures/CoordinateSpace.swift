public import Core

/// A reference frame for gesture event locations.
///
/// Terminal UI ships `.local` (origin at the gesture's target rect) and
/// `.global` (origin at the terminal canvas). `.named(_:)` is reserved
/// in SwiftUI's shape but is not yet supported — calling it at resolve
/// time traps with a clear message.
public struct CoordinateSpace: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case local
    case global
    case named(String)
  }

  public let kind: Kind

  private init(kind: Kind) {
    self.kind = kind
  }

  public static let local = CoordinateSpace(kind: .local)
  public static let global = CoordinateSpace(kind: .global)

  public static func named(_ name: some Hashable & Sendable) -> CoordinateSpace {
    CoordinateSpace(kind: .named(String(describing: name)))
  }

  /// Resolves a terminal-global cell point into this coordinate space,
  /// given the hit-tested target rect.
  public func resolve(
    terminalPoint: Point,
    targetRect: CellRect
  ) -> Point {
    switch kind {
    case .local:
      return Point(
        x: terminalPoint.x - Double(targetRect.origin.x),
        y: terminalPoint.y - Double(targetRect.origin.y)
      )
    case .global:
      return terminalPoint
    case .named(let name):
      fatalError(
        "CoordinateSpace.named(\"\(name)\") is not yet supported in "
          + "TerminalUI. Use .local or .global, or file an issue if "
          + "you need named coordinate frames."
      )
    }
  }
}
