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

/// A fully-qualified matched-geometry identifier: the namespace
/// plus the user-provided hashable ID, erased to a string for
/// cross-frame lookup.
public struct MatchedGeometryKey: Hashable, Sendable {
  public let namespace: MatchedGeometryNamespace
  /// The erased string form of the caller ID.
  /// Two `Hashable` values collide if their `String(describing:)` output is the same.
  /// Use distinct namespaces if you require stronger uniqueness.
  public let id: String

  public init(namespace: MatchedGeometryNamespace, id: String) {
    self.namespace = namespace
    self.id = id
  }

  public init<ID: Hashable>(namespace: MatchedGeometryNamespace = .default, id: ID) {
    self.namespace = namespace
    self.id = String(describing: id)
  }
}

/// The configuration for one view instance.
/// A resolved or placed node stores it with a ``MatchedGeometryKey``.
/// The configuration currently stores only the `isSource` flag.
/// Future fields can include opt-out values for individual properties.
public struct MatchedGeometryConfig: Equatable, Sendable {
  public var key: MatchedGeometryKey
  /// Whether this view supplies its geometry as the "from" source for the match.
  /// If multiple views share a key in one frame, the last depth-first walk supplies the source.
  /// A view with `isSource: false` does not supply the source.
  /// This behavior matches the `isSource` parameter of SwiftUI `matchedGeometryEffect(id:in:properties:anchor:isSource:)`.
  public var isSource: Bool

  public init(key: MatchedGeometryKey, isSource: Bool = true) {
    self.key = key
    self.isSource = isSource
  }
}
