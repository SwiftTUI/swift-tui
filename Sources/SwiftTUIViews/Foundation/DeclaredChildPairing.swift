import SwiftTUICore

// Pairing the two declared-child traversals.
//
// A lazy container (today: `TabView`) needs two things per declared child, and
// `DeclaredChildrenView` produces them through separate traversals:
//
// - `enumerateDeclaredChildren` hands back the raw child view so metadata can
//   be peeked WITHOUT resolving — inactive tabs must not fire `.onAppear` or
//   `.task`.
// - `appendScopedDeclaredChildren` hands back a deferred payload that resolves
//   the child later, rebased onto the placement root it ends up under.
//
// They cannot currently be one traversal: the payload's whole purpose is to
// postpone context derivation until placement is known, while the peek must
// happen now. What ties them together is position — the Nth enumerated child
// must be the Nth payload — and that correspondence is asserted nowhere. The
// protocol asks implementations to "increment `nextIndex` the same way", which
// is prose across five conformers and four traversals.
//
// This file is where the correspondence lives, so a caller cannot re-derive it
// by hand and quietly get it wrong.

/// One declared child, paired with the payload that will resolve it.
@MainActor
package struct PairedDeclaredChild {
  /// The raw declared view, boxed so a caller can inspect conformances without
  /// resolving it.
  package let view: Any

  /// The deferred payload for this child, or `nil` when the payload traversal
  /// yielded fewer children than the enumeration did.
  ///
  /// A `nil` here is not "this child has no content" — it is the traversals
  /// disagreeing, and it always comes with a ``PairedDeclaredChildren/divergence``.
  package let payload: LazySubviewPayload?
}

/// How far the two traversals disagreed over the same content value.
package struct DeclaredChildTraversalDivergence: Sendable, Equatable {
  package let enumeratedCount: Int
  package let payloadCount: Int

  package init(
    enumeratedCount: Int,
    payloadCount: Int
  ) {
    self.enumeratedCount = enumeratedCount
    self.payloadCount = payloadCount
  }
}

/// Declared children with their deferred payloads, plus whether the two
/// traversals that produced them agreed.
@MainActor
package struct PairedDeclaredChildren {
  package let children: [PairedDeclaredChild]

  /// Non-`nil` when the traversals disagreed about how many children the same
  /// content declares.
  ///
  /// Worth reporting rather than absorbing: past the first mismatched child,
  /// every later child is paired with some *other* child's payload, so a tab
  /// renders a sibling's body. Nothing downstream can detect that — both
  /// halves are individually well-formed.
  package let divergence: DeclaredChildTraversalDivergence?
}

/// Enumerates `view`'s declared children and pairs each with its deferred
/// payload by declared position.
///
/// Position is the only correspondence available: the payload traversal has no
/// view to match on, and the enumeration has no payload to match on. Both walk
/// the same `DeclaredChildrenView` structure with the same index discipline, so
/// agreement is expected — but it is checked here rather than assumed, and a
/// short payload list degrades to `nil` payloads *with* a divergence record
/// instead of silently.
@MainActor
package func pairedLazyDeclaredChildren<V: View>(
  from view: V,
  in context: ResolveContext,
  kindName: String,
  debugName: String,
  origin: LazySubviewPayloadOrigin = .tabBody,
  lifecyclePolicy: LazySubviewLifecyclePolicy = .activeOnly
) -> PairedDeclaredChildren {
  let payloads = lazyDeclaredBuilderChildren(
    from: view,
    debugName: debugName,
    origin: origin,
    lifecyclePolicy: lifecyclePolicy
  )

  var children: [PairedDeclaredChild] = []
  var nextIndex = 0
  enumerateDeclaredChildViews(
    view,
    in: context,
    kindName: kindName,
    nextIndex: &nextIndex
  ) { child, _, _ in
    let position = children.count
    children.append(
      PairedDeclaredChild(
        view: child,
        payload: payloads.indices.contains(position) ? payloads[position] : nil
      )
    )
  }

  let divergence =
    children.count == payloads.count
    ? nil
    : DeclaredChildTraversalDivergence(
      enumeratedCount: children.count,
      payloadCount: payloads.count
    )

  return PairedDeclaredChildren(
    children: children,
    divergence: divergence
  )
}

extension DeclaredChildTraversalDivergence {
  /// The reportable form of a disagreement, for a container that pairs the
  /// traversals.
  package func runtimeIssue(
    container: String,
    identity: Identity
  ) -> RuntimeIssue {
    RuntimeIssue(
      severity: .warning,
      code: "structure.declaredChildTraversalMismatch",
      message:
        "\(container) enumerated \(enumeratedCount) declared children but the "
        + "payload traversal produced \(payloadCount); children past the first "
        + "mismatch are paired with the wrong content.",
      identity: identity,
      source: "DeclaredChildrenView"
    )
  }
}
