import Testing

@testable import SwiftTUIGraph

/// The removal-policy table, and what a descent inherits from it.
///
/// Three independent booleans were threaded through every recursive call of the
/// subtree-removal cascade — eight expressible combinations for four real call
/// shapes. The presets are now the vocabulary, and this pins them, because a
/// preset silently gaining or losing a guard changes which nodes a teardown
/// keeps and shows up only as a leak or a stranded island much later.
struct SubtreeRemovalPolicyTests {
  @Test("ordinary removal trusts every guard and spares nothing")
  func ordinaryPolicy() {
    let policy = SubtreeRemovalPolicy.ordinary
    #expect(!policy.sparesVisitedDescendants)
    #expect(policy.consultsLifetimeAnchors)
    #expect(policy.appliesParentDetachedKeepGuard)
  }

  @Test("reconciliation teardown spares visited descendants")
  func sparingPolicy() {
    let policy = SubtreeRemovalPolicy.sparingVisitedDescendants
    #expect(policy.sparesVisitedDescendants)
    #expect(policy.consultsLifetimeAnchors)
    #expect(policy.appliesParentDetachedKeepGuard)
  }

  @Test("collapse absorption stops trusting lifetime anchors")
  func absorbingPolicy() {
    // The target's remaining anchors are inside the cascade, so they prove
    // nothing — but that is a fact about the target, not the tree beneath it,
    // so descendants are still spared.
    let policy = SubtreeRemovalPolicy.absorbingIntoCollapse
    #expect(policy.sparesVisitedDescendants)
    #expect(!policy.consultsLifetimeAnchors)
    #expect(policy.appliesParentDetachedKeepGuard)
  }

  @Test("barrier adjudication drops the keep-guard for the root only")
  func barrierPolicy() {
    // Reachability already proved this root dead, so its liveness proxies must
    // not re-spare it: a stranded island root keeps its identity index entry
    // precisely because no teardown path ever reached it.
    let policy = SubtreeRemovalPolicy.barrierAdjudicated
    #expect(policy.sparesVisitedDescendants)
    #expect(policy.consultsLifetimeAnchors)
    #expect(!policy.appliesParentDetachedKeepGuard)
  }

  @Test("a descent inherits the spare decision and nothing else")
  func descentInheritsOnlyTheSpareDecision() {
    // The load-bearing rule, previously an accident of default parameter
    // values at each recursive call: barrier adjudication and collapse
    // absorption are claims about one node, so a descendant must not inherit
    // them. Inheriting `barrierAdjudicated` would drop the keep-guard for a
    // whole subtree that was never adjudicated.
    for policy in [
      SubtreeRemovalPolicy.ordinary,
      .sparingVisitedDescendants,
      .absorbingIntoCollapse,
      .barrierAdjudicated,
    ] {
      let descent = policy.forDescent
      #expect(descent.sparesVisitedDescendants == policy.sparesVisitedDescendants)
      #expect(descent.consultsLifetimeAnchors)
      #expect(descent.appliesParentDetachedKeepGuard)
    }
  }

  @Test("descent is idempotent")
  func descentIsIdempotent() {
    // Nested descents must not drift: the cascade applies `forDescent` at every
    // level, so it has to be a fixed point after the first application.
    for policy in [
      SubtreeRemovalPolicy.ordinary,
      .sparingVisitedDescendants,
      .absorbingIntoCollapse,
      .barrierAdjudicated,
    ] {
      #expect(policy.forDescent.forDescent == policy.forDescent)
    }
  }

  @Test("derivations change exactly one axis")
  func derivationsAreNarrow() {
    let base = SubtreeRemovalPolicy.ordinary
    #expect(base.sparingVisitedDescendants(true).sparesVisitedDescendants)
    #expect(base.sparingVisitedDescendants(true).consultsLifetimeAnchors)
    #expect(base.sparingVisitedDescendants(true).appliesParentDetachedKeepGuard)

    #expect(!base.ignoringLifetimeAnchors(true).consultsLifetimeAnchors)
    #expect(!base.ignoringLifetimeAnchors(true).sparesVisitedDescendants)
    #expect(base.ignoringLifetimeAnchors(true).appliesParentDetachedKeepGuard)
  }
}
