package import SwiftTUICore

// MARK: - Built-In Item Models

/// Visual chrome treatment applied to a prompt presentation's surface.
///
/// Sheets, alerts, and confirmation dialogs share one rendering path;
/// this enum selects how the chrome around the content is drawn.
public enum PresentationChrome: Equatable, Sendable {
  /// Default: rounded inset surface with a foreground-tint stroke on
  /// every side. Used by alerts, confirmation dialogs, and standard
  /// sheets.
  case surface

  /// Flat, edge-to-edge strip with no side or top border and a single
  /// soft divider along the bottom that reads like a shadow under the
  /// content. Used for command-palette dropdowns and similar banners
  /// that should read as part of the window chrome rather than a
  /// floating card.
  case dropdown

  /// Compact, intrinsic-width bordered box with no header — the
  /// rendering used by `Menu` to float its expanded content above the
  /// surrounding layout without reflowing siblings. Smaller and
  /// chromier than `.surface` (no title row, no close button), this
  /// chrome anchors at the presentation's `alignment` and sizes to its
  /// content rather than expanding to fill.
  case menu
}

/// Controls how a prompt presentation surface accepts the full-screen
/// portal overlay proposal.
package enum PromptPresentationContentSizing: Equatable, Sendable {
  /// Let the surface consume the host proposal. This preserves the
  /// existing sheet/dropdown behavior where content can expand to the
  /// available presentation area.
  case fillAvailable

  /// Measure the surface at its intrinsic size before placing it in the
  /// full-screen portal overlay. Used by compact floating presentations
  /// such as menus, where internal spacers must not stretch rows to the
  /// terminal width.
  case intrinsic
}

package struct PromptPresentationDescriptor: Equatable, Sendable {
  package enum BodyMode: Equatable, Sendable {
    case contentOnly
    case messageAndActions
  }

  package var alignment: Alignment
  package var accessibilityRole: AccessibilityRole
  package var backdropOpacity: Double
  package var defaultDismissTitle: String
  package var headerTone: TerminalTone
  package var minWidth: Int
  package var maxWidth: Int?
  package var scrollMinHeight: Int
  package var scrollIdealHeight: Int
  package var scrollMaxHeight: Int
  package var bodyMode: BodyMode
  package var chrome: PresentationChrome
  package var borderStyle: StrokeStyle
  package var contentSizing: PromptPresentationContentSizing
  package var createsFocusScope: Bool

  package init(
    alignment: Alignment,
    accessibilityRole: AccessibilityRole,
    backdropOpacity: Double,
    defaultDismissTitle: String,
    headerTone: TerminalTone,
    minWidth: Int,
    maxWidth: Int? = nil,
    scrollMinHeight: Int,
    scrollIdealHeight: Int,
    scrollMaxHeight: Int,
    bodyMode: BodyMode,
    chrome: PresentationChrome = .surface,
    borderStyle: StrokeStyle = StrokeStyle(borderSet: .innerHalfBlock, placement: .outset),
    contentSizing: PromptPresentationContentSizing = .fillAvailable,
    createsFocusScope: Bool = true
  ) {
    self.alignment = alignment
    self.accessibilityRole = accessibilityRole
    self.backdropOpacity = backdropOpacity
    self.defaultDismissTitle = defaultDismissTitle
    self.headerTone = headerTone
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.scrollMinHeight = scrollMinHeight
    self.scrollIdealHeight = scrollIdealHeight
    self.scrollMaxHeight = scrollMaxHeight
    self.bodyMode = bodyMode
    self.chrome = chrome
    self.borderStyle = borderStyle
    self.contentSizing = contentSizing
    self.createsFocusScope = createsFocusScope
  }
}

package protocol PortalPresentationItem: Identifiable, Sendable where ID == String {
  var portalEntryID: PortalEntryID { get }
}

package struct PromptPresentationItem: PortalPresentationItem {
  package var id: String
  package var portalEntryID: PortalEntryID
  package var title: String
  package var descriptor: PromptPresentationDescriptor
  package var actionPayloads: [PortalAttachmentPayload]
  package var messagePayloads: [PortalAttachmentPayload]
  package var contentPayloads: [PortalAttachmentPayload]
  package var dismiss: @MainActor @Sendable () -> Void

  @MainActor
  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    title: String,
    descriptor: PromptPresentationDescriptor,
    actionPayloads: [PortalAttachmentPayload],
    messagePayloads: [PortalAttachmentPayload],
    contentPayloads: [PortalAttachmentPayload],
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    let portalEntryID = portalEntryID ?? fallbackPortalEntryID(for: id)
    let edge = PortalAttachmentEdge(portalEntryID: portalEntryID)
    self.id = id
    self.portalEntryID = portalEntryID
    self.title = title
    self.descriptor = descriptor
    self.actionPayloads = actionPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.messagePayloads = messagePayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.contentPayloads = contentPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.dismiss = dismiss
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
  package var presentation: ToastStylePresentation
  package var duration: Double?
  package var dismiss: @MainActor @Sendable () -> Void

  @MainActor
  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    contentPayloads: [PortalAttachmentPayload],
    presentation: ToastStylePresentation,
    duration: Double?,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    let portalEntryID = portalEntryID ?? fallbackPortalEntryID(for: id)
    let edge = PortalAttachmentEdge(
      portalEntryID: portalEntryID,
      modalPolicy: .nonModal
    )
    self.id = id
    self.portalEntryID = portalEntryID
    self.contentPayloads = contentPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.presentation = presentation
    self.duration = duration
    self.dismiss = dismiss
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
