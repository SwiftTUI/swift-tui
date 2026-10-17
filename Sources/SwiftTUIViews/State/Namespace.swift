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

/// A property wrapper that allocates a stable, opaque namespace ID
/// scoped to the enclosing view's identity.
///
/// This wrapper matches the SwiftUI `@Namespace` API.
/// Declare `@Namespace var ns` on a view.
/// Then pass `ns` to `.matchedGeometryEffect(id:in:)` to scope matched-geometry IDs.
/// The same string key can then identify unrelated views without a collision.
///
/// The namespace ID is stable across renders of the same view
/// instance (re-uses `@State`-backed storage keyed by the property
/// wrapper's source location).  A brand-new namespace ID is
/// allocated when storage for that mounted owner is initialized.
@propertyWrapper
@MainActor
public struct Namespace: Sendable {
  /// Opaque identifier type exposed to user code.  Equal to
  /// `MatchedGeometryNamespace` so it can flow through the Core
  /// module's matched-geometry machinery.
  public typealias ID = MatchedGeometryNamespace

  private let state: State<ID>

  public init(line: UInt = #line, column: UInt = #column) {
    state = State(
      initialValueFactory: { MatchedGeometryNamespaceAllocator.next() },
      line: line,
      column: column
    )
  }

  public var wrappedValue: ID {
    state.wrappedValue
  }
}

// The dynamic-property and capture passes recurse into the nested State,
// qualifying its slot by this namespace declaration's property path.
extension Namespace: DynamicProperty {
  public func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }
}
