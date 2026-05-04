import Synchronization

/// An opaque reference to a value derived from a view's placed geometry.
///
/// Anchor values are safe to store in ordinary preferences. Resolve them
/// against concrete layout using `GeometryProxy`.
public struct Anchor<Value: Sendable>: Equatable, Hashable, Sendable {
  package var payload: AnchorPayload

  package init(
    identity: Identity,
    kind: AnchorKind
  ) {
    payload = AnchorPayload(
      identity: identity,
      kind: kind
    )
  }
}

/// A geometry value that can be captured as an anchor preference.
public struct AnchorSource<Value: Sendable>: Equatable, Hashable, Sendable {
  package var kind: AnchorKind

  package init(kind: AnchorKind) {
    self.kind = kind
  }
}

extension AnchorSource where Value == Rect {
  /// Captures the bounds of the modified view.
  public static var bounds: Self {
    Self(kind: .bounds)
  }
}

extension AnchorSource where Value == Point {
  public static var topLeading: Self {
    Self(kind: .point(.topLeading))
  }

  public static var top: Self {
    Self(kind: .point(.top))
  }

  public static var topTrailing: Self {
    Self(kind: .point(.topTrailing))
  }

  public static var leading: Self {
    Self(kind: .point(.leading))
  }

  public static var center: Self {
    Self(kind: .point(.center))
  }

  public static var trailing: Self {
    Self(kind: .point(.trailing))
  }

  public static var bottomLeading: Self {
    Self(kind: .point(.bottomLeading))
  }

  public static var bottom: Self {
    Self(kind: .point(.bottom))
  }

  public static var bottomTrailing: Self {
    Self(kind: .point(.bottomTrailing))
  }
}

package enum AnchorKind: Equatable, Hashable, Sendable {
  case bounds
  case point(UnitPoint)
}

package struct AnchorPayload: Equatable, Hashable, Sendable {
  package var identity: Identity
  package var kind: AnchorKind

  package init(
    identity: Identity,
    kind: AnchorKind
  ) {
    self.identity = identity
    self.kind = kind
  }
}

package struct GeometryResolutionDiagnostics: Equatable, Sendable {
  package var anchorResolutionMissCount: Int
  package var firstAnchorResolutionMissIdentity: Identity?
  package var missingNamedCoordinateSpaceCount: Int
  package var firstMissingNamedCoordinateSpaceName: String?
  package var duplicateNamedCoordinateSpaceCount: Int
  package var firstDuplicateNamedCoordinateSpaceName: String?

  package init(
    anchorResolutionMissCount: Int = 0,
    firstAnchorResolutionMissIdentity: Identity? = nil,
    missingNamedCoordinateSpaceCount: Int = 0,
    firstMissingNamedCoordinateSpaceName: String? = nil,
    duplicateNamedCoordinateSpaceCount: Int = 0,
    firstDuplicateNamedCoordinateSpaceName: String? = nil
  ) {
    self.anchorResolutionMissCount = anchorResolutionMissCount
    self.firstAnchorResolutionMissIdentity = firstAnchorResolutionMissIdentity
    self.missingNamedCoordinateSpaceCount = missingNamedCoordinateSpaceCount
    self.firstMissingNamedCoordinateSpaceName = firstMissingNamedCoordinateSpaceName
    self.duplicateNamedCoordinateSpaceCount = duplicateNamedCoordinateSpaceCount
    self.firstDuplicateNamedCoordinateSpaceName = firstDuplicateNamedCoordinateSpaceName
  }
}

package final class GeometryResolutionDiagnosticsRecorder: Sendable {
  private let state = Mutex(GeometryResolutionDiagnostics())

  package init() {}

  package var snapshot: GeometryResolutionDiagnostics {
    state.withLock { $0 }
  }

  package func recordAnchorResolutionMiss(
    identity: Identity
  ) {
    state.withLock {
      $0.anchorResolutionMissCount += 1
      if $0.firstAnchorResolutionMissIdentity == nil {
        $0.firstAnchorResolutionMissIdentity = identity
      }
    }
  }

  package func recordMissingNamedCoordinateSpace(
    name: String
  ) {
    state.withLock {
      $0.missingNamedCoordinateSpaceCount += 1
      if $0.firstMissingNamedCoordinateSpaceName == nil {
        $0.firstMissingNamedCoordinateSpaceName = name
      }
    }
  }

  package func recordDuplicateNamedCoordinateSpace(
    name: String
  ) {
    state.withLock {
      $0.duplicateNamedCoordinateSpaceCount += 1
      if $0.firstDuplicateNamedCoordinateSpaceName == nil {
        $0.firstDuplicateNamedCoordinateSpaceName = name
      }
    }
  }
}

package struct PlacedFrameTable: Equatable, Sendable {
  package private(set) var framesByIdentity: [Identity: CellRect]
  package private(set) var namedCoordinateSpaces: [String: CellRect]
  package private(set) var namedCoordinateSpaceIdentities: [String: Identity]
  package let diagnosticsRecorder: GeometryResolutionDiagnosticsRecorder?

  package init(
    framesByIdentity: [Identity: CellRect] = [:],
    namedCoordinateSpaces: [String: CellRect] = [:],
    namedCoordinateSpaceIdentities: [String: Identity] = [:],
    diagnosticsRecorder: GeometryResolutionDiagnosticsRecorder? = nil
  ) {
    self.framesByIdentity = framesByIdentity
    self.namedCoordinateSpaces = namedCoordinateSpaces
    self.namedCoordinateSpaceIdentities = namedCoordinateSpaceIdentities
    self.diagnosticsRecorder = diagnosticsRecorder
  }

  package static func == (
    lhs: Self,
    rhs: Self
  ) -> Bool {
    lhs.framesByIdentity == rhs.framesByIdentity
      && lhs.namedCoordinateSpaces == rhs.namedCoordinateSpaces
      && lhs.namedCoordinateSpaceIdentities == rhs.namedCoordinateSpaceIdentities
  }

  package var geometryResolutionDiagnostics: GeometryResolutionDiagnostics {
    diagnosticsRecorder?.snapshot ?? .init()
  }

  package mutating func record(
    identity: Identity,
    bounds: CellRect,
    namedCoordinateSpaceName: String?
  ) {
    framesByIdentity[identity] = bounds

    if let namedCoordinateSpaceName {
      if let existingIdentity = namedCoordinateSpaceIdentities[namedCoordinateSpaceName],
        existingIdentity != identity
      {
        diagnosticsRecorder?.recordDuplicateNamedCoordinateSpace(
          name: namedCoordinateSpaceName
        )
      }
      namedCoordinateSpaceIdentities[namedCoordinateSpaceName] = identity
      namedCoordinateSpaces[namedCoordinateSpaceName] = bounds
    }
  }

  package func frame(
    for identity: Identity
  ) -> CellRect? {
    guard let frame = framesByIdentity[identity] else {
      diagnosticsRecorder?.recordAnchorResolutionMiss(identity: identity)
      return nil
    }
    return frame
  }
}
