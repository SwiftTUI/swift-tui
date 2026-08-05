public import SwiftTUICore

/// A reference frame for gesture event locations.
///
/// Terminal UI supplies `.local`, `.global`, and `.named(_:)`.
/// `.local` has its origin at the target rectangle of the gesture.
/// `.global` has its origin at the terminal canvas.
/// `.named(_:)` identifies frames that ``View/coordinateSpace(_:)`` records.
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
    resolve(
      terminalPoint: terminalPoint,
      targetRect: targetRect,
      namedCoordinateSpaces: namedCoordinateSpaces,
      diagnosticsRecorder: nil
    )
  }

  /// Resolves a terminal-global continuous point into this coordinate space,
  /// recording deterministic diagnostics for geometry-proxy fallbacks.
  package func resolve(
    terminalPoint: Point,
    targetRect: CellRect,
    namedCoordinateSpaces: [String: CellRect],
    diagnosticsRecorder: GeometryResolutionDiagnosticsRecorder?
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
        diagnosticsRecorder?.recordMissingNamedCoordinateSpace(name: name)
        return terminalPoint
      }
      return Point(
        x: terminalPoint.x - Double(frame.origin.x),
        y: terminalPoint.y - Double(frame.origin.y)
      )
    }
  }

  /// Resolves a terminal-global continuous rect into this coordinate space,
  /// using the named coordinate-space frames extracted for the current frame.
  package func resolve(
    terminalRect: Rect,
    targetRect: CellRect,
    namedCoordinateSpaces: [String: CellRect]
  ) -> Rect {
    resolve(
      terminalRect: terminalRect,
      targetRect: targetRect,
      namedCoordinateSpaces: namedCoordinateSpaces,
      diagnosticsRecorder: nil
    )
  }

  /// Resolves a terminal-global continuous rect into this coordinate space,
  /// recording deterministic diagnostics for geometry-proxy fallbacks.
  package func resolve(
    terminalRect: Rect,
    targetRect: CellRect,
    namedCoordinateSpaces: [String: CellRect],
    diagnosticsRecorder: GeometryResolutionDiagnosticsRecorder?
  ) -> Rect {
    Rect(
      origin: resolve(
        terminalPoint: terminalRect.origin,
        targetRect: targetRect,
        namedCoordinateSpaces: namedCoordinateSpaces,
        diagnosticsRecorder: diagnosticsRecorder
      ),
      size: terminalRect.size
    )
  }
}

/// A named reference frame established by ``View/coordinateSpace(_:)``.
///
/// Construct with ``named(_:)`` and resolve gesture locations against the
/// frame via ``CoordinateSpace/named(_:)`` using the same name.
public struct NamedCoordinateSpace: Equatable, Sendable {
  package let name: String

  private init(name: String) {
    self.name = name
  }

  /// Creates a named coordinate space with the given name.
  public static func named(_ name: some Hashable & Sendable) -> NamedCoordinateSpace {
    NamedCoordinateSpace(name: String(describing: name))
  }

  /// The equivalent gesture-resolution coordinate space.
  public var coordinateSpace: CoordinateSpace {
    .named(name)
  }
}
