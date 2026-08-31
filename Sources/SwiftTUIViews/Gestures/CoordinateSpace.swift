public import SwiftTUICore

/// A reference frame for gesture event locations.
///
/// Terminal UI supplies `.local`, `.global`, and `.named(_:)`.
/// `.local` has its origin at the target rectangle of the gesture.
/// `.global` has its origin at the terminal canvas.
/// `.named(_:)` identifies frames that ``View/coordinateSpace(_:)`` records.
///
/// A named space is identified by the typed value passed to ``named(_:)``,
/// not by its text: `.named(1)` and `.named("1")` are different spaces. See
/// `NamedCoordinateSpace`.
public struct CoordinateSpace: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case local
    case global
    case named(NamedCoordinateSpace)
  }

  public let kind: Kind

  package init(kind: Kind) {
    self.kind = kind
  }

  public static let local = CoordinateSpace(kind: .local)
  public static let global = CoordinateSpace(kind: .global)

  public static func named(_ name: some Hashable & Sendable) -> CoordinateSpace {
    CoordinateSpace(kind: .named(.named(name)))
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
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect]
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
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect],
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
    case .named(let space):
      guard let frame = namedCoordinateSpaces[space] else {
        diagnosticsRecorder?.recordMissingNamedCoordinateSpace(name: space.description)
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
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect]
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
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect],
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

extension NamedCoordinateSpace {
  /// The equivalent gesture-resolution coordinate space.
  public var coordinateSpace: CoordinateSpace {
    CoordinateSpace(kind: .named(self))
  }
}
