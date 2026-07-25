import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// The declared-builder consumption tail, and the reporting policies that
/// differ between its call sites.
///
/// Drop-empty / splice-group / pass-through was written out at three sites.
/// They agreed on the shape and disagreed on *reporting*: whether the detached
/// mint left behind gets anchored to the nearest declaring host. Those
/// differences are now named policies, so a new consumption site has to pick
/// one deliberately instead of copying whichever neighbour it read first.
@MainActor
struct DeclaredChildConsumptionTests {
  private func identity() -> Identity {
    testIdentity("DeclaredChildConsumption", "Child")
  }

  private func node(kind: NodeKind, identity: Identity) -> ResolvedNode {
    ResolvedNode(identity: identity, kind: kind, children: [])
  }

  @Test("an unmodified empty element is dropped")
  func unmodifiedEmptyIsDropped() {
    let consumed = consumeDeclaredChild(
      node(kind: .view("EmptyView"), identity: identity()),
      resolvedUnder: identity(),
      in: nil,
      policy: .declaredBuilder
    )
    #expect(consumed.isEmpty)
  }

  @Test("an unmodified group is spliced into its children")
  func unmodifiedGroupIsSpliced() {
    let childA = node(kind: .view("Text"), identity: identity().child(.named("a")))
    let childB = node(kind: .view("Text"), identity: identity().child(.named("b")))
    var group = node(kind: .view("Group"), identity: identity())
    group.children = [childA, childB]

    let consumed = consumeDeclaredChild(
      group,
      resolvedUnder: identity(),
      in: nil,
      policy: .declaredBuilder
    )
    #expect(consumed.count == 2)
    #expect(consumed.map(\.identity) == [childA.identity, childB.identity])
  }

  @Test("anything else passes through as one child")
  func ordinaryChildPassesThrough() {
    let text = node(kind: .view("Text"), identity: identity())
    let consumed = consumeDeclaredChild(
      text,
      resolvedUnder: identity(),
      in: nil,
      policy: .declaredBuilder
    )
    #expect(consumed.count == 1)
    #expect(consumed[0].identity == text.identity)
  }

  @Test("a re-rooted result is never dropped or spliced")
  func reRootedResultPassesThrough() {
    // The identity guard is what makes drop/splice apply to *unmodified*
    // results only: any modifier in the child re-roots the result away from
    // the identity it resolved under, and it must then survive as a child.
    // Without this, a modified `Group` would have its children lifted and the
    // modifier silently discarded.
    let elsewhere = testIdentity("DeclaredChildConsumption", "Modified")
    var group = node(kind: .view("Group"), identity: elsewhere)
    group.children = [node(kind: .view("Text"), identity: elsewhere.child(.named("a")))]

    let consumed = consumeDeclaredChild(
      group,
      resolvedUnder: identity(),
      in: nil,
      policy: .declaredBuilder
    )
    #expect(consumed.count == 1)
    #expect(consumed[0].identity == elsewhere)

    let empty = node(kind: .view("EmptyView"), identity: elsewhere)
    let consumedEmpty = consumeDeclaredChild(
      empty,
      resolvedUnder: identity(),
      in: nil,
      policy: .declaredBuilder
    )
    #expect(consumedEmpty.count == 1)
  }

  @Test("the shipped policies differ only where they are documented to")
  func policiesArePinned() {
    // These three are the whole reporting matrix. The differences are about
    // EAGERNESS only — `closeResolveLifetimeScope` anchors any observed node
    // that reaches close unowned, so no preset decides whether a mint survives
    // (see DroppedElementAnchoringTests). Pinned so the matrix cannot drift
    // without a decision.
    #expect(DeclaredChildConsumptionPolicy.declaredBuilder.reportsDroppedEmpty)
    #expect(DeclaredChildConsumptionPolicy.declaredBuilder.reportsSplicedGroup)

    #expect(!DeclaredChildConsumptionPolicy.forEachIteration.reportsDroppedEmpty)
    #expect(DeclaredChildConsumptionPolicy.forEachIteration.reportsSplicedGroup)

    #expect(!DeclaredChildConsumptionPolicy.indexedChildRealization.reportsDroppedEmpty)
    #expect(!DeclaredChildConsumptionPolicy.indexedChildRealization.reportsSplicedGroup)
  }

  @Test("splicing and dropping are policy-independent")
  func policyDoesNotChangeTheSplice() {
    // Reporting is about lifetime anchoring, never about what the container
    // receives — every policy must return the same children.
    let child = node(kind: .view("Text"), identity: identity().child(.named("a")))
    var group = node(kind: .view("Group"), identity: identity())
    group.children = [child]

    for policy in [
      DeclaredChildConsumptionPolicy.declaredBuilder,
      .forEachIteration,
      .indexedChildRealization,
    ] {
      #expect(
        consumeDeclaredChild(group, resolvedUnder: identity(), in: nil, policy: policy)
          .map(\.identity) == [child.identity]
      )
      #expect(
        consumeDeclaredChild(
          node(kind: .view("EmptyView"), identity: identity()),
          resolvedUnder: identity(),
          in: nil,
          policy: policy
        ).isEmpty
      )
    }
  }
}
