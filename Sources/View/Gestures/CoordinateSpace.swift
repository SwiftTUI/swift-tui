public import Core

/// A reference frame for gesture event locations.
///
/// Terminal UI ships `.local` (origin at the gesture's target rect), `.global`
/// (origin at the terminal canvas), and `.named(_:)` for frames recorded by
/// ``View/coordinateSpace(name:)``.
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

  /// Resolves a terminal-global continuous point into this coordinate space,
  /// given the hit-tested target rect.
  public func resolve(
    terminalPoint: Point,
    targetRect: CellRect
  ) -> Point {
    resolve(
      terminalPoint: terminalPoint,
      targetRect: targetRect,
      namedCoordinateSpaces: [:]
    )
  }

  /// Resolves a terminal-global continuous point into this coordinate space,
  /// using the named coordinate-space frames extracted for the current frame.
  package func resolve(
    terminalPoint: Point,
    targetRect: CellRect,
    namedCoordinateSpaces: [String: CellRect]
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
      guard let frame = namedCoordinateSpaces[name] else {
        return terminalPoint
      }
      return Point(
        x: terminalPoint.x - Double(frame.origin.x),
        y: terminalPoint.y - Double(frame.origin.y)
      )
    }
  }
}
