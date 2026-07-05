package import SwiftTUICore

package struct OverlayStackEntry: Sendable {
  package var id: String
  package var portalEntryID: PortalEntryID?
  package var ordering: PortalOrdering
  package var kindName: String
  package var modalPolicy: PortalModalPolicy
  package var acceptsEscape: Bool
  package var dismiss: (@MainActor @Sendable () -> Void)?
  package var payload: PortalAttachmentPayload

  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    ordering: PortalOrdering,
    kindName: String,
    modalPolicy: PortalModalPolicy,
    acceptsEscape: Bool,
    dismiss: (@MainActor @Sendable () -> Void)?,
    payload: PortalAttachmentPayload
  ) {
    self.id = id
    self.portalEntryID = portalEntryID
    self.ordering = ordering
    self.kindName = kindName
    self.modalPolicy = modalPolicy
    self.acceptsEscape = acceptsEscape
    self.dismiss = dismiss
    self.payload = payload
  }

  package var surfaceStableKey: String {
    portalEntryID?.placementStableKey ?? id
  }

  package func declarationOwnerEdge(
    placementRoot: StructuralPath
  ) -> DeclarationOwnerEdge? {
    portalEntryID?.declarationOwnerEdge(placementRoot: placementRoot)
  }
}

@MainActor
package func composeOverlayStackTree(
  baseNode: ResolvedNode,
  entries: [OverlayStackEntry],
  in context: ResolveContext
) -> ResolvedNode {
  guard !entries.isEmpty else {
    return baseNode
  }

  let sortedEntries = entries.sorted {
    portalOrderingPrecedes($0.ordering, $1.ordering)
  }
  let disablesBaseInteraction = sortedEntries.contains {
    $0.modalPolicy == .disablesBaseInteraction
  }
  let hostContext = context.child(component: .named("PortalHost"))
  var overlayContext = hostContext.child(component: .named("overlays"))
  // Retained-subtree reuse is value-blind: it serves the committed overlays
  // subtree whenever this identity's subtree does not intersect the frame's
  // invalidation set — and an overlay-entry set change never invalidates it
  // (the activation flip dirties the trigger leaf and the portal root, not
  // this host). A 0↔1 transition restructures the wrapper above, but
  // 1→2 / 2→1 transitions change only this host's children, so the stale
  // entry list is served verbatim: a second presentation never appears and a
  // dismissed one never leaves the screen (its strand then shadows the
  // reopened entry's routes — the "undismissable sheet"). Mark the subtree
  // churned when the composed entry list differs from the committed children
  // so the host re-resolves fresh; surviving entries keep their runtime
  // state (slots key off their stable identities).
  let desiredEntryIdentities = sortedEntries.map { entry in
    overlayContext.identity.child("entry:\(entry.id)")
  }
  if let committedOverlayHost = context.viewGraph?.nodeForIdentity(overlayContext.identity),
    committedOverlayHost.children.map(\.identity) != desiredEntryIdentities
  {
    overlayContext.withinChurnedSubtree = true
  }
  let overlayNode = resolveView(
    OverlayStackOverlayHost(entries: sortedEntries),
    in: overlayContext
  )

  var hostedBaseNode = baseNode
  hostedBaseNode.semanticMetadata.focusScopeBoundary = false
  if disablesBaseInteraction {
    hostedBaseNode.semanticMetadata = hostedBaseNode.semanticMetadata.merging(
      SemanticMetadata(
        interactionAvailability: .disabled(reason: .modalOverlay)
      )
    )
  }

  var stackSemantics = SemanticMetadata()
  stackSemantics.focusScopeBoundary = true
  if baseNode.semanticMetadata.focusScopeBoundary {
    stackSemantics.focusScopeIdentity = baseNode.identity
  }

  return ResolvedNode(
    identity: context.identity,
    structuralPath: context.structuralPath,
    kind: .view("OverlayStack"),
    children: [hostedBaseNode, overlayNode],
    environmentSnapshot: hostContext.environment,
    transactionSnapshot: hostContext.transaction,
    layoutBehavior: .overlay(alignment: .topLeading),
    surfaceComposition: .init(
      role: .stackingContext,
      stableKey: "overlay-stack:\(context.structuralPath.description)",
      invalidationScope: .fullSurfaceDiff
    ),
    semanticMetadata: stackSemantics
  )
}

@MainActor
private struct OverlayStackOverlayHost: PrimitiveView, ResolvableView {
  var entries: [OverlayStackEntry]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let children = entries.map { entry in
      let entryContext = context.child(
        component: .init(rawValue: "entry:\(entry.id)")
      )
      return resolveView(
        OverlayStackEntryHost(entry: entry),
        in: entryContext
      )
    }

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("OverlayStackOverlays"),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .overlay(alignment: .topLeading),
        surfaceComposition: .init(
          role: .detachedOverlayHost,
          stableKey: "overlay-host:\(context.structuralPath.description)",
          invalidationScope: .fullSurfaceDiff
        )
      )
    ]
  }
}

@MainActor
private struct OverlayStackEntryHost: PrimitiveView, ResolvableView {
  var entry: OverlayStackEntry

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let bodyContext = context.child(component: .named("body"))
    let bodyNode = entry.payload.resolve(in: bodyContext)
    var entryNode = ResolvedNode(
      identity: context.identity,
      structuralEdgeRole: .detachedOverlayEntry,
      kind: .view(entry.kindName),
      children: [bodyNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      surfaceComposition: .init(
        role: .detachedOverlayEntry,
        stableKey: entry.surfaceStableKey,
        invalidationScope: .fullSurfaceDiff
      )
    )
    entryNode.declarationOwnerEdge = entry.declarationOwnerEdge(
      placementRoot: context.structuralPath
    )

    return [
      entryNode
    ]
  }
}
