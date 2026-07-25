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

/// Which detached mints a consumption site anchors to its declaring host.
///
/// The three shipped policies differ, and the differences are load-bearing
/// enough to name rather than average away.
package struct DeclaredChildConsumptionPolicy: Sendable, Equatable {
  /// Anchor the node left behind when an empty element is dropped.
  package var reportsDroppedEmpty: Bool
  /// Anchor the node left behind when a group is spliced.
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

  /// `ForEach` iterations: splices are anchored, drops are not.
  ///
  /// UNEXPLAINED DIVERGENCE, preserved as-found rather than normalised. The
  /// declared-builder walk anchors a dropped empty element for reasons that
  /// appear to apply here too, and no comment or test records why this path
  /// differs. Changing it is a behavioural change to lifetime anchoring, so it
  /// wants its own investigation and its own gate — not a silent ride-along in
  /// a refactor.
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
