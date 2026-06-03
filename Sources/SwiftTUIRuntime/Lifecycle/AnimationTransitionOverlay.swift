import SwiftTUICore
import SwiftTUIViews

enum AnimationTransitionOverlay {
  typealias ResolvedInjection = (childIndex: Int, snapshot: ResolvedNode)

  /// Interpolates from a starting opacity toward removal modifiers.
  ///
  /// `progress == 0` means the removal is just starting from the displayed
  /// state; `progress == 1` means the removal reached the target modifiers.
  static func interpolatedRemovalModifiers(
    from startOpacity: Double,
    to target: TransitionModifiers,
    progress: Double
  ) -> TransitionModifiers {
    var result = TransitionModifiers.identity
    if let targetOpacity = target.opacity {
      result.opacity = startOpacity + (targetOpacity - startOpacity) * progress
    }
    if let targetOffsetX = target.offsetX {
      result.offsetX = Int(Double(targetOffsetX) * progress)
    }
    if let targetOffsetY = target.offsetY {
      result.offsetY = Int(Double(targetOffsetY) * progress)
    }
    return result
  }

  /// Builds the resolved-level fallback snapshot for a removal overlay.
  ///
  /// This keeps transient marking coupled to modifier application so callers
  /// cannot accidentally re-inject a semantic/lifecycle-visible removal clone.
  static func resolvedRemovalSnapshot(
    from snapshot: ResolvedNode,
    applying modifiers: TransitionModifiers
  ) -> ResolvedNode {
    var copy = snapshot
    markTransient(&copy)
    applyTransitionModifiersRecursively(modifiers, to: &copy)
    return copy
  }

  /// Walks the current tree and injects removal snapshots at their previous
  /// parent identity and child index. If the previous index exceeds the
  /// current children count, the snapshot is appended at the end.
  static func injectResolvedRemovals(
    into tree: ResolvedNode,
    injectionsByParent: [Identity: [ResolvedInjection]]
  ) -> ResolvedNode {
    var node = tree
    // Recurse first so child injections happen before parent-level
    // splicing; this preserves the visual order of nested removals.
    var children = node.children.map { child in
      injectResolvedRemovals(into: child, injectionsByParent: injectionsByParent)
    }
    if let injections = injectionsByParent[node.identity] {
      let sorted = injections.sorted { $0.childIndex < $1.childIndex }
      for injection in sorted {
        let insertIndex = min(injection.childIndex, children.count)
        children.insert(injection.snapshot, at: insertIndex)
      }
    }
    node.children = children
    return node
  }

  private static func markTransient(_ node: inout ResolvedNode) {
    node.isTransient = true
    node.structuralEdgeRole = .transientRemovalOverlay
    node.surfaceComposition.role = .transientRemovalOverlay
    var children = node.children
    for i in children.indices {
      markTransient(&children[i])
    }
    node.setChildrenPreservingDerivedState(children)
  }

  /// Applies transition modifiers recursively to every node in the subtree.
  ///
  /// Opacity cascades because rasterization reads per-node opacity and text
  /// leaves need to see it. Offset applies only at the subtree root, either by
  /// rewriting an intrinsic root, composing with an existing offset, or wrapping
  /// non-offset layout in a stable private offset node.
  private static func applyTransitionModifiersRecursively(
    _ modifiers: TransitionModifiers,
    to node: inout ResolvedNode
  ) {
    if let opacity = modifiers.opacity {
      var drawMetadata = node.drawMetadata
      let base = drawMetadata.baseStyle.explicitOpacity ?? 1.0
      drawMetadata.baseStyle.explicitOpacity = base * opacity
      node.drawMetadata = drawMetadata
    }

    var children = node.children
    for i in children.indices {
      var child = children[i]
      var childMods = TransitionModifiers.identity
      childMods.opacity = modifiers.opacity
      applyTransitionModifiersRecursively(childMods, to: &child)
      children[i] = child
    }
    node.setChildrenPreservingDerivedState(children)

    let offsetX = modifiers.offsetX ?? 0
    let offsetY = modifiers.offsetY ?? 0
    guard offsetX != 0 || offsetY != 0 else { return }

    switch node.layoutBehavior {
    case .intrinsic:
      node.layoutBehavior = .offset(x: offsetX, y: offsetY)

    case .offset(let existingX, let existingY):
      node.setLayoutBehaviorPreservingDerivedState(
        .offset(x: existingX + offsetX, y: existingY + offsetY)
      )

    default:
      let wrapperIdentity = Identity(
        components: node.identity.components + ["__transitionOffset"]
      )
      var wrapped = ResolvedNode(
        identity: wrapperIdentity,
        structuralEdgeRole: .transientRemovalOverlay,
        kind: .view("TransitionOffset"),
        children: [node],
        environmentSnapshot: node.environmentSnapshot,
        transactionSnapshot: node.transactionSnapshot,
        layoutBehavior: .offset(x: offsetX, y: offsetY),
        surfaceComposition: .init(role: .transientRemovalOverlay)
      )
      wrapped.isTransient = node.isTransient
      node = wrapped
    }
  }
}
