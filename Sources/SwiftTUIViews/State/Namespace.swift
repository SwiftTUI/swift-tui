public import SwiftTUICore
import Synchronization

/// Monotonically allocates opaque namespace identifiers for
/// `@Namespace` property wrappers.  Starts at 1 so that the
/// 0-valued ``MatchedGeometryNamespace/default`` stays reserved
/// for call sites that opt out of scoping.
package enum MatchedGeometryNamespaceAllocator {
  private static let counter = Atomic<UInt64>(0)

  package static func next() -> MatchedGeometryNamespace {
    let value = counter.wrappingAdd(1, ordering: .relaxed).newValue
    return MatchedGeometryNamespace(value)
  }
}

private enum NamespaceStorageKey: Hashable {
  case unmounted
  case mounted(StructuralPath)
}

/// A property wrapper that allocates a stable, opaque namespace ID
/// scoped to the enclosing view's identity.
///
/// Matches SwiftUI's `@Namespace` ergonomics: declare `@Namespace
/// var ns` on a view, then pass `ns` into
/// `.matchedGeometryEffect(id:in:)` to scope matched-geometry IDs
/// so the same string key can refer to unrelated views in different
/// parts of the hierarchy without colliding.
///
/// The namespace ID is stable across renders of the same view
/// instance (re-uses `@State`-backed storage keyed by the property
/// wrapper's source location).  A brand-new namespace ID is
/// allocated the first time the view at a given identity evaluates
/// its body.
@propertyWrapper
@MainActor
public struct Namespace: Sendable {
  /// Opaque identifier type exposed to user code.  Equal to
  /// ``MatchedGeometryNamespace`` so it can flow through the Core
  /// module's matched-geometry machinery.
  public typealias ID = MatchedGeometryNamespace

  private let state: State<[NamespaceStorageKey: ID]>

  public init(line: UInt = #line, column: UInt = #column) {
    state = State(
      wrappedValue: [:],
      line: line,
      column: column
    )
  }

  public var wrappedValue: ID {
    let key =
      currentAuthoringContext().map { NamespaceStorageKey.mounted($0.structuralPath) }
      ?? .unmounted
    if let existing = state.wrappedValue[key] {
      return existing
    }
    let allocated = MatchedGeometryNamespaceAllocator.next()
    state.wrappedValue[key] = allocated
    return allocated
  }
}
