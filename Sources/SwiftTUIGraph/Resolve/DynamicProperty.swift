/// The reuse certification produced by one dynamic-property update.
public enum DynamicPropertyUpdateResult: Equatable, Sendable {
  /// The property registered every dependency and certifies that its
  /// evaluation-visible result did not change.
  case unchanged
  /// The property's evaluation-visible result changed during this update.
  case changed
  /// The property cannot certify reuse transparency.
  case uncertified

  package func merging(_ other: Self) -> Self {
    switch (self, other) {
    case (.uncertified, _), (_, .uncertified):
      return .uncertified
    case (.changed, _), (_, .changed):
      return .changed
    case (.unchanged, .unchanged):
      return .unchanged
    }
  }
}

/// A lifetime-scoped route from asynchronous custom storage back to the view
/// graph that registered it.
///
/// A lease does not expose its graph node or authored identity. Calling
/// ``invalidate()`` after that node or graph departs is harmless.
public final class DynamicPropertyInvalidationLease: Sendable {
  private let invalidateClosure: @Sendable () -> Void

  package init(_ invalidate: @escaping @Sendable () -> Void) {
    invalidateClosure = invalidate
  }

  /// Requests a new evaluation of the lease's live owner.
  ///
  /// This method may be called from any executor.
  public nonisolated func invalidate() {
    invalidateClosure()
  }

  package static let inert = DynamicPropertyInvalidationLease {}
}

/// Per-evaluation services available to a custom dynamic property.
public struct DynamicPropertyContext: Sendable {
  /// A graph- and node-scoped invalidation route for asynchronous storage.
  public let invalidationLease: DynamicPropertyInvalidationLease

  package init(invalidationLease: DynamicPropertyInvalidationLease) {
    self.invalidationLease = invalidationLease
  }
}

/// A stored property of a view (or of another dynamic property) that the
/// framework updates before each body evaluation.
///
/// The framework runs ``update(in:)`` through the container copy that the
/// *next body evaluation consumes*, so a plain stored mutation is visible to
/// that body and to every closure it creates. Composed built-in wrappers and
/// reference storage keep working exactly as before; a non-mutating
/// implementation still satisfies the requirement.
///
/// The in-place guarantee holds for a dynamic property that is a strongly
/// stored, statically typed field of a struct container — the shape every
/// property wrapper declaration produces. In an enum container, or in a field
/// whose *static* type is existential (`Any`, `any Protocol`), the framework
/// updates a copy and a stored mutation is not written back; debug builds
/// report such a discard as a soundness violation.
///
/// A conforming type is a value type — a struct or an enum — like the views
/// and modifiers that hold it. Class-typed *fields* stay unrestricted.
@MainActor
public protocol DynamicProperty {
  /// Refreshes the property's state before the enclosing body evaluates.
  ///
  /// Nested dynamic properties update first. The default is conservative:
  /// third-party storage that does not explicitly certify transparency denies
  /// retained and memoized reuse.
  @MainActor
  mutating func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _dynamicPropertyValueTypeWitness: Void { get }
}

extension DynamicProperty {
  @MainActor
  public mutating func update(in context: DynamicPropertyContext)
    -> DynamicPropertyUpdateResult
  {
    .uncertified
  }
}

extension DynamicProperty {
  @_documentation(visibility: internal)
  public static var _dynamicPropertyValueTypeWitness: Void { () }
}

extension DynamicProperty where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI dynamic properties must be value types (a struct or an enum); a class cannot conform to DynamicProperty"
  )
  public static var _dynamicPropertyValueTypeWitness: Void { () }
}

/// Framework-owned properties whose update never retains or fires the context
/// lease. Package-only so third-party properties cannot accidentally opt out
/// of the live invalidation route promised by their public context.
package protocol DynamicPropertyLeaseIndependent: DynamicProperty {}

/// Graph-slot-backed property storage whose authored wrapper value carries no
/// additional evaluation input. Memo comparison may omit these fields because
/// their visible values are covered by graph dependencies. Package-only:
/// custom wrappers must keep their own configuration in the value comparison.
package protocol DynamicPropertyMemoStorageOnly: DynamicProperty {}

package struct DynamicPropertyLeaseRegistrationKey: Hashable, Sendable {
  package var containerTypeName: String
  package var structuralPath: String
  var fieldPath: String
  var occurrenceOrdinal: Int
}

@MainActor
private enum DynamicPropertyLeaseTokenSource {
  private static var nextToken: UInt64 = 0

  static func issue(
    containerType: Any.Type,
    structuralPath: String,
    fieldPath: String
  ) -> DynamicPropertyInvalidationLease {
    guard
      let node = ViewNodeContext.current,
      let graph = node.ownerGraph
    else {
      return .inert
    }
    let graphScope = StateGraphScopeID(graph)
    let nodeID = node.viewNodeID
    let occurrenceOrdinal = node.claimDynamicPropertyLeaseOccurrenceOrdinal()
    let key = DynamicPropertyLeaseRegistrationKey(
      containerTypeName: String(reflecting: containerType),
      structuralPath: structuralPath,
      fieldPath: fieldPath,
      occurrenceOrdinal: occurrenceOrdinal
    )
    nextToken &+= 1
    let token = nextToken
    node.registerDynamicPropertyLease(key, token: token)

    return DynamicPropertyInvalidationLease {
      Task { @MainActor in
        guard
          let liveGraph = LiveViewGraphRegistry.graph(for: graphScope),
          let liveNode = liveGraph.nodeForViewNodeID(nodeID),
          liveNode.isDynamicPropertyLeaseCurrent(key, token: token)
        else {
          return
        }
        liveNode.invalidator?.requestInvalidation(of: [liveNode.identity])
      }
    }
  }
}

extension DynamicPropertyContext {
  package static let leaseIndependent = Self(invalidationLease: .inert)

  @MainActor
  package static func current(
    containerType: Any.Type,
    structuralPath: String,
    fieldPath: String
  ) -> Self {
    Self(
      invalidationLease: DynamicPropertyLeaseTokenSource.issue(
        containerType: containerType,
        structuralPath: structuralPath,
        fieldPath: fieldPath
      )
    )
  }
}
