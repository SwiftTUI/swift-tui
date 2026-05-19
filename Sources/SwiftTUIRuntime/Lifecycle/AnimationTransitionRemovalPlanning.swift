import SwiftTUICore

/// Pure planning helpers for transition removal overlays.
///
/// When a view carrying a `.transition()` modifier leaves the tree, the
/// animation controller re-injects its previous subtree as a non-semantic
/// overlay each tick until the exit animation finishes. That overlay has to be
/// injected at a *stable* point in the surviving tree, and choosing it is a
/// pure computation over the previous frame's structure.
///
/// This file owns that computation. The controller keeps ownership of the
/// animation-state mutation that consumes the result.
enum AnimationTransitionRemovalPlanning {
  /// The point at which a removal overlay subtree should be re-injected.
  struct InjectionPoint {
    /// Deepest disappearing ancestor — the root of the subtree to inject so
    /// the entire wrapped layout unit fades out together.
    var target: Identity
    /// First surviving ancestor the overlay attaches to. `nil` (or a still-
    /// removed identity) means the walk-up stopped at a multi-child container
    /// and the caller cannot inject the overlay.
    var parent: Identity?
  }

  /// Resolves where a removed identity's transition overlay should be injected.
  ///
  /// The `.transition()` modifier is registered against the leaf identity its
  /// child resolved to, but that leaf may be wrapped by layout modifiers
  /// (`.padding(1)`, `.frame`, `.offset`, …) which have their own identities
  /// and disappear at the same time. We walk up the previous parent chain to
  /// find the deepest disappearing ancestor (the subtree to inject) and the
  /// first surviving ancestor (the insertion point).
  ///
  /// The walk only passes through *single-child* wrapper nodes. A removed
  /// ancestor with multiple children is a structural container (VStack,
  /// HStack, ScrollView, …); climbing past it would capture an entire
  /// unrelated subtree as the removal overlay — the failure mode seen during a
  /// tab switch where a `PhaseAnimator`'s frame-level `.animate` leaks into the
  /// transition. Stopping at such a container leaves `parent` pointing at a
  /// still-removed identity, which the caller converts into a skip.
  static func injectionPoint(
    for identity: Identity,
    previousRoot: ResolvedNode,
    previousParentByIdentity: [Identity: Identity],
    newIdentities: Set<Identity>
  ) -> InjectionPoint {
    var injectionTarget = identity
    var injectionParent = previousParentByIdentity[identity]
    while let parent = injectionParent, !newIdentities.contains(parent) {
      // Stop before climbing through a multi-child container.
      if let parentNode = AnimationTreeQueries.findResolvedNode(
        in: previousRoot,
        identity: parent
      ),
        parentNode.children.count > 1
      {
        break
      }
      injectionTarget = parent
      injectionParent = previousParentByIdentity[parent]
    }
    return InjectionPoint(target: injectionTarget, parent: injectionParent)
  }
}
