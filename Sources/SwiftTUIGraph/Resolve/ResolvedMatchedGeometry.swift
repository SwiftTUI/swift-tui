public import SwiftTUIPrimitives

/// An opaque namespace used to scope matched-geometry IDs so the
/// same string-or-hashable key can refer to unrelated views in
/// different parts of the hierarchy.
///
/// It has the same structure as SwiftUI `Namespace.ID`, but it does not require the `@Namespace` property wrapper.
/// Call sites can use ``default`` for one global namespace.
/// They can also pass a distinct value for each namespace.
public struct MatchedGeometryNamespace: Hashable, Sendable {
  public let rawValue: UInt64
  public init(_ rawValue: UInt64) { self.rawValue = rawValue }
  public static let `default` = MatchedGeometryNamespace(0)
}

/// A caller's typed identifier scoped to its matched-geometry namespace.
public struct MatchedGeometryKey: Hashable, Sendable {
  public let namespace: MatchedGeometryNamespace
  public let id: AnyID

  public init<ID: Hashable & Sendable>(namespace: MatchedGeometryNamespace = .default, id: ID) {
    self.namespace = namespace
    self.id = AnyID(id)
  }
}

/// The geometry a matched pair interpolates.
///
/// Matches SwiftUI's `MatchedGeometryProperties`: `.position` tracks the
/// anchor point, `.size` interpolates the size, and `.frame` is both.
public struct MatchedGeometryProperties: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The view's position: its anchor point slides from the source's anchor
  /// point to the destination's.
  public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
  /// The view's size: its bounds resize from the source's size to the
  /// destination's.
  public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
  /// Both position and size.
  public static let frame: MatchedGeometryProperties = [.position, .size]
}

/// The configuration for one view instance.
/// A resolved or placed node stores it with a ``MatchedGeometryKey``.
public struct MatchedGeometryConfig: Equatable, Sendable {
  public var key: MatchedGeometryKey
  /// Whether this view supplies its geometry as the "from" source for the match.
  /// If multiple views share a key in one frame, the last depth-first walk supplies the source.
  /// A view with `isSource: false` does not supply the source.
  /// This behavior matches the `isSource` parameter of SwiftUI `matchedGeometryEffect(id:in:properties:anchor:isSource:)`.
  public var isSource: Bool
  /// The properties the match interpolates for this instance (the
  /// destination's configuration governs a swap).
  public var properties: MatchedGeometryProperties
  /// The point, in unit coordinates, that ``properties`` positions and
  /// sizes are measured around.
  public var anchor: UnitPoint

  public init(
    key: MatchedGeometryKey,
    isSource: Bool = true,
    properties: MatchedGeometryProperties = .frame,
    anchor: UnitPoint = .center
  ) {
    self.key = key
    self.isSource = isSource
    self.properties = properties
    self.anchor = anchor
  }
}
