import SwiftTUICore

// The declared-builder consumption tail.
//
// A container that splices a resolved child into its own children array has to
// answer the same three-case question every time: an unmodified `EmptyView` at
// the child's own identity is dropped, an unmodified `Group` at that identity
// is spliced (its children lifted into the enclosing array), and anything else
// passes through as one child.
//
// Both dropped and spliced nodes were minted by `resolveView` and then end up
// in no children array, so they are *detached*: reporting one to
// resolve-lifetime scope both marks it observed and anchors its lifetime to
// the nearest declaring host. Failing to report leaves the mint unanchored.
//
// The shape was written out at three sites. They did NOT agree about
// reporting, and that disagreement is preserved here as a named policy rather
// than quietly normalised — see ``DeclaredChildConsumptionPolicy``.

/// Which detached mints a consumption site anchors *eagerly*.
///
/// "Eagerly" is the whole content of these flags. Anchoring itself is
/// guaranteed by `closeResolveLifetimeScope`, which owns any observed node that
/// reaches scope close without a durable owner; reporting at consumption time
/// only moves the same anchor, to the same host, earlier in the same scope.
/// The three shipped policies differ, and are named rather than averaged away
/// because the reasons differ — but none of them decides whether a mint
/// survives.
package struct DeclaredChildConsumptionPolicy: Sendable, Equatable {
  /// Eagerly anchor the node left behind when an empty element is dropped.
  package var reportsDroppedEmpty: Bool
  /// Eagerly anchor the node left behind when a group is spliced.
  package var reportsSplicedGroup: Bool

  /// Declared-builder child walks and outline rows: both mints are anchored.
  ///
  /// A dropped value still minted a stored node (a `_ = state` Void expression
  /// or an explicit `EmptyView`; TimelineView's `timelineBody` is the shipped
  /// shape), and a spliced group's own node owns that row's `@State`.
  package static let declaredBuilder = Self(
    reportsDroppedEmpty: true,
    reportsSplicedGroup: true
  )

  /// `ForEach` iterations: splices are anchored eagerly, drops are not.
  ///
  /// Investigated rather than inherited. The difference is timing only, not
  /// whether the mint gets an owner: `resolveView` reports every result to the
  /// enclosing lifetime scope, and `closeResolveLifetimeScope` anchors any
  /// observed node that reaches close without a durable owner — to that same
  /// enclosing host. A dropped row is therefore anchored either way; reporting
  /// here would only move the anchor earlier in the same scope.
  ///
  /// Confirmed by A/B: flipping ``declaredBuilder``'s drop reporting off leaves
  /// its dropped elements anchored and the unclassified-node probe flat.
  /// `DroppedElementAnchoringTests` pins both paths.
  package static let forEachIteration = Self(
    reportsDroppedEmpty: false,
    reportsSplicedGroup: true
  )

  /// Indexed-child realization: nothing is anchored here.
  ///
  /// Realized rows are consumed by a source that owns their lifetime through
  /// the indexed-child machinery instead of resolve-lifetime scope, so an
  /// anchor at the declaring host would be the wrong owner.
  package static let indexedChildRealization = Self(
    reportsDroppedEmpty: false,
    reportsSplicedGroup: false
  )
}

/// Consumes one resolved declared child, returning what the enclosing
/// container should splice into its children.
///
/// `identity` is the identity the child resolved under: the drop and splice
/// legs apply only to an *unmodified* result — a node that still carries that
/// identity. A modifier anywhere in the child re-roots the result, and it then
/// passes through as an ordinary child.
@MainActor
package func consumeDeclaredChild(
  _ resolved: ResolvedNode,
  resolvedUnder identity: Identity,
  in viewGraph: ViewGraph?,
  policy: DeclaredChildConsumptionPolicy
) -> [ResolvedNode] {
  guard resolved.identity == identity else {
    return [resolved]
  }

  switch resolved.kind {
  case .view("EmptyView"):
    if policy.reportsDroppedEmpty {
      viewGraph?.reportDetachedResolvedLifetimeResult(resolved)
    }
    return []
  case .view("Group"):
    if policy.reportsSplicedGroup {
      viewGraph?.reportDetachedResolvedLifetimeResult(resolved)
    }
    return resolved.children
  default:
    return [resolved]
  }
}
