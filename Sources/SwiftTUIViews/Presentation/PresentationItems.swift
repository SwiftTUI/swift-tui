import SwiftTUICore

/// The declaration captures its style environment before the presentation
/// trigger is evaluated. Even a closed declaration therefore records its
/// style read and cannot retain a stale style across an environment change.
package struct PreparedPortalSurface: Sendable {
  package var make:
    @MainActor @Sendable (_ hasMessage: Bool, _ hasActions: Bool) -> PortalSurfacePresentation
}

/// Placement and a typed surface resolver selected by the declaration.
/// No originating-kind, body-mode, or chrome discriminator crosses this seam.
package struct PortalSurfacePresentation: Sendable {
  package var alignment: Alignment
  package var backdropOpacity: Double
  package var hostInsets: EdgeInsets
  package var isIntrinsic: Bool
  package var accessibilityRole: AccessibilityRole
  package var createsFocusScope: Bool
  private var resolveBody:
    @MainActor @Sendable (PromptPresentationItem, ResolveContext) -> ResolvedNode

  package init<Content: View>(
    alignment: Alignment,
    backdropOpacity: Double = 0,
    hostInsets: EdgeInsets = .zero,
    isIntrinsic: Bool = false,
    accessibilityRole: AccessibilityRole,
    createsFocusScope: Bool = true,
    @ViewBuilder content: @escaping @MainActor @Sendable (PromptPresentationItem) -> Content
  ) {
    self.alignment = alignment
    self.backdropOpacity = backdropOpacity
    self.hostInsets = hostInsets
    self.isIntrinsic = isIntrinsic
    self.accessibilityRole = accessibilityRole
    self.createsFocusScope = createsFocusScope
    self.resolveBody = { item, context in resolveView(content(item), in: context) }
  }

  @MainActor
  package func resolve(_ item: PromptPresentationItem, in context: ResolveContext) -> ResolvedNode {
    resolveBody(item, context)
  }

  package var semanticMetadata: SemanticMetadata {
    let metadata = SemanticMetadata(accessibilityRole: accessibilityRole)
    return createsFocusScope
      ? metadata.merging(focusStructureMetadata(scopeBoundary: true)) : metadata
  }
}

package protocol PortalPresentationItem: Identifiable, Sendable where ID == String {
  var portalEntryID: PortalEntryID { get }
  var entryDismissObserver: (@MainActor @Sendable () -> Void)? { get }
}

package struct PromptPresentationItem: PortalPresentationItem {
  package var id: String
  package var portalEntryID: PortalEntryID
  package var title: String
  package var surface: PortalSurfacePresentation
  package var actionPayloads: [PortalAttachmentPayload]
  package var messagePayloads: [PortalAttachmentPayload]
  package var contentPayloads: [PortalAttachmentPayload]
  package var dismiss: @MainActor @Sendable () -> Void
  package var onDismiss: (@MainActor @Sendable () -> Void)?

  package var entryDismissObserver: (@MainActor @Sendable () -> Void)? {
    onDismiss
  }

  @MainActor
  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    title: String,
    surface: PreparedPortalSurface,
    actionPayloads: [PortalAttachmentPayload],
    messagePayloads: [PortalAttachmentPayload],
    contentPayloads: [PortalAttachmentPayload],
    dismiss: @escaping @MainActor @Sendable () -> Void,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) {
    let portalEntryID = portalEntryID ?? fallbackPortalEntryID(for: id)
    let edge = PortalAttachmentEdge(portalEntryID: portalEntryID)
    self.id = id
    self.portalEntryID = portalEntryID
    self.title = title
    self.surface = surface.make(
      messagePayloads.contains { $0.hasDeclaredContent },
      actionPayloads.contains { $0.hasDeclaredContent })
    self.actionPayloads = actionPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.messagePayloads = messagePayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.contentPayloads = contentPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.dismiss = dismiss
    self.onDismiss = onDismiss
  }
}

package struct PopoverPresentationItem: PortalPresentationItem {
  package var id: String
  package var portalEntryID: PortalEntryID
  package var sourceIdentity: Identity
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var modalPolicy: PortalModalPolicy
  package var surfaceItem: PromptPresentationItem

  package var entryDismissObserver: (@MainActor @Sendable () -> Void)? {
    surfaceItem.onDismiss
  }

  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    sourceIdentity: Identity,
    attachmentAnchor: PopoverAttachmentAnchor,
    arrowEdge: Edge?,
    modalPolicy: PortalModalPolicy,
    surfaceItem: PromptPresentationItem
  ) {
    self.id = id
    self.portalEntryID = portalEntryID ?? surfaceItem.portalEntryID
    self.sourceIdentity = sourceIdentity
    self.attachmentAnchor = attachmentAnchor
    self.arrowEdge = arrowEdge
    self.modalPolicy = modalPolicy
    self.surfaceItem = surfaceItem
  }
}

package struct ToastPresentationItem: PortalPresentationItem {
  package var id: String
  package var portalEntryID: PortalEntryID
  package var contentPayloads: [PortalAttachmentPayload]
  /// The declaration's style, resolved at composition time — a toast's
  /// `stackIndex`/`stackCount` are only known once the coordinator has
  /// composed the active stack.
  package var style: AnyToastStyle
  package var duration: Double?
  package var dismiss: @MainActor @Sendable () -> Void
  package var onDismiss: (@MainActor @Sendable () -> Void)?

  // A toast overlay can host several independently-lived items. Each toast
  // row registers its own committed disappearance observer instead of using
  // the family overlay entry root.
  package var entryDismissObserver: (@MainActor @Sendable () -> Void)? {
    nil
  }

  @MainActor
  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    contentPayloads: [PortalAttachmentPayload],
    style: AnyToastStyle,
    duration: Double?,
    dismiss: @escaping @MainActor @Sendable () -> Void,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) {
    let portalEntryID = portalEntryID ?? fallbackPortalEntryID(for: id)
    let edge = PortalAttachmentEdge(
      portalEntryID: portalEntryID,
      modalPolicy: .nonModal
    )
    self.id = id
    self.portalEntryID = portalEntryID
    self.contentPayloads = contentPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.style = style
    self.duration = duration
    self.dismiss = dismiss
    self.onDismiss = onDismiss
  }
}

@MainActor
package func presentationDismissObserver(
  _ onDismiss: (@MainActor @Sendable () -> Void)?,
  authoringContext: AuthoringContext?
) -> (@MainActor @Sendable () -> Void)? {
  guard let onDismiss else {
    return nil
  }
  return { [authoringContext] in
    withAuthoringContext(authoringContext) {
      onDismiss()
    }
  }
}

package func presentationAttachment(
  for node: ResolvedNode,
  token: String
) -> PortalEntryID {
  PortalEntryID(
    sourceIdentity: node.identity,
    sourceStructuralPath: node.structuralPath,
    sourceEntityIdentity: node.entityIdentity,
    token: token
  )
}

package func presentationAttachmentID(
  for sourceIdentity: Identity,
  token: String
) -> String {
  "\(sourceIdentity.path)#\(token)"
}

private func fallbackPortalEntryID(
  for id: String
) -> PortalEntryID {
  PortalEntryID(
    sourceIdentity: Identity(components: ["__ImperativePresentation", id]),
    token: id
  )
}
