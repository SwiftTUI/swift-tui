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

package struct PlacedFrameTable: Equatable, Sendable {
  package private(set) var framesByIdentity: [Identity: CellRect]
  package private(set) var namedCoordinateSpaces: [String: CellRect]

  package init(
    framesByIdentity: [Identity: CellRect] = [:],
    namedCoordinateSpaces: [String: CellRect] = [:]
  ) {
    self.framesByIdentity = framesByIdentity
    self.namedCoordinateSpaces = namedCoordinateSpaces
  }

  package mutating func record(
    identity: Identity,
    bounds: CellRect,
    namedCoordinateSpaceName: String?
  ) {
    framesByIdentity[identity] = bounds

    if let namedCoordinateSpaceName {
      namedCoordinateSpaces[namedCoordinateSpaceName] = bounds
    }
  }

  package func frame(
    for identity: Identity
  ) -> CellRect? {
    framesByIdentity[identity]
  }
}
