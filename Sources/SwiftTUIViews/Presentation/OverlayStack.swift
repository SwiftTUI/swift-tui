package import SwiftTUICore

package struct OverlayStackEntry: Sendable {
  package var id: String
  package var ordering: PortalOrdering
  package var kindName: String
  package var modalPolicy: PortalModalPolicy
  package var acceptsEscape: Bool
  package var dismiss: (@MainActor @Sendable () -> Void)?
  package var payload: PortalContentPayload

  package init(
    id: String,
    ordering: PortalOrdering,
    kindName: String,
    modalPolicy: PortalModalPolicy,
    acceptsEscape: Bool,
    dismiss: (@MainActor @Sendable () -> Void)?,
    payload: PortalContentPayload
  ) {
    self.id = id
    self.ordering = ordering
    self.kindName = kindName
    self.modalPolicy = modalPolicy
    self.acceptsEscape = acceptsEscape
    self.dismiss = dismiss
    self.payload = payload
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
  let overlayContext = hostContext.child(component: .named("overlays"))
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
    kind: .view("OverlayStack"),
    children: [hostedBaseNode, overlayNode],
    environmentSnapshot: hostContext.environment,
    transactionSnapshot: hostContext.transaction,
    layoutBehavior: .overlay(alignment: .topLeading),
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
        layoutBehavior: .overlay(alignment: .topLeading)
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

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view(entry.kindName),
        children: [bodyNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}
