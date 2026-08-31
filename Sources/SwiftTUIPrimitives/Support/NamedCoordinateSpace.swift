/// A named reference frame established by `View.coordinateSpace(_:)`.
///
/// Construct one with ``named(_:)`` and resolve gesture locations or
/// `GeometryProxy` frames against it through `CoordinateSpace.named(_:)`
/// using the same name.
///
/// The name is a typed identity, not a string. Two spaces are the same space
/// only when their names have the same type and compare equal: `.named(1)`
/// and `.named("1")` are distinct spaces, as are two enum cases from different
/// enums whose cases print alike. ``description`` is the name's diagnostic
/// spelling (`String(describing:)` of the name). It appears in frame
/// diagnostics and never takes part in equality or hashing.
public struct NamedCoordinateSpace: Hashable, Sendable, CustomStringConvertible {
  /// One immutable allocation per name. The value rides in every
  /// `SemanticMetadata`, and so in every resolved node; storing the identity
  /// existential and the spelling behind a single reference keeps that inline
  /// footprint at one pointer instead of ~56 bytes, which is what the
  /// phase-product size budgets (deep-tree teardown) police.
  private final class Storage: Sendable {
    let identity: AnyID
    let description: String

    init(identity: AnyID, description: String) {
      self.identity = identity
      self.description = description
    }
  }

  private let storage: Storage

  /// Type-sensitive identity: equal only for the same name type and value.
  package var identity: AnyID {
    storage.identity
  }

  /// The name's diagnostic spelling.
  ///
  /// Stable for logs and frame diagnostics. Not an identity: distinct spaces
  /// may share a description.
  public var description: String {
    storage.description
  }

  package init<Name: Hashable & Sendable>(_ name: Name) {
    storage = Storage(identity: AnyID(name), description: String(describing: name))
  }

  /// Creates a named coordinate space with the given name.
  public static func named(_ name: some Hashable & Sendable) -> NamedCoordinateSpace {
    NamedCoordinateSpace(name)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage === rhs.storage || lhs.storage.identity == rhs.storage.identity
  }

  public func hash(into hasher: inout Hasher) {
    storage.identity.hash(into: &hasher)
  }
}
