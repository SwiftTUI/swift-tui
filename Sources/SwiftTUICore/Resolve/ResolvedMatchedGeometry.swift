/// An opaque namespace used to scope matched-geometry IDs so the
/// same string-or-hashable key can refer to unrelated views in
/// different parts of the hierarchy.
///
/// Mirrors SwiftUI's `Namespace.ID` shape but without the
/// `@Namespace` property-wrapper ceremony — call sites either use
/// ``default`` for a single global namespace or pass a distinct
/// value per namespace.
public struct MatchedGeometryNamespace: Hashable, Sendable {
  public let rawValue: UInt64
  public init(_ rawValue: UInt64) { self.rawValue = rawValue }
  public static let `default` = MatchedGeometryNamespace(0)
}

/// A fully-qualified matched-geometry identifier — the namespace
/// plus the user-provided hashable ID, erased to a string for
/// cross-frame lookup.
public struct MatchedGeometryKey: Hashable, Sendable {
  public let namespace: MatchedGeometryNamespace
  /// The erased string form of the caller's ID.  Two calls with
  /// `Hashable` values whose `String(describing:)` output matches
  /// will collide — callers needing stronger uniqueness should use
  /// distinct namespaces.
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

/// Per-view-instance configuration carried alongside a
/// ``MatchedGeometryKey`` on a resolved/placed node.  Currently
/// only the `isSource` flag is stored; future extensions (e.g.
/// per-property opt-outs) land here.
public struct MatchedGeometryConfig: Equatable, Sendable {
  public var key: MatchedGeometryKey
  /// Whether this view contributes its geometry as the "from"
  /// source for the match.  When multiple views share the same
  /// key in the same frame, the last depth-first walk wins as the
  /// source; views marked `isSource: false` never contribute.
  /// Matches SwiftUI's `matchedGeometryEffect(id:in:properties:anchor:isSource:)`
  /// semantics for the `isSource` parameter.
  public var isSource: Bool

  public init(key: MatchedGeometryKey, isSource: Bool = true) {
    self.key = key
    self.isSource = isSource
  }
}
