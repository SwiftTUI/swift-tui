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
    @MainActor @Sendable (PromptPresentationItem, ResolveContext) -> ResolveWork<ResolvedNode>

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
    self.resolveBody = { item, context in resolveViewWork(content(item), in: context) }
  }

  @MainActor
  package func resolve(_ item: PromptPresentationItem, in context: ResolveContext) -> ResolvedNode {
    resolveBody(item, context).run()
  }

  @MainActor
  package func resolveWork(_ item: PromptPresentationItem, in context: ResolveContext)
    -> ResolveWork<ResolvedNode>
  {
    resolveBody(item, context)
  }

  package var semanticMetadata: SemanticMetadata {
    let metadata = SemanticMetadata(accessibilityRole: accessibilityRole)
    return createsFocusScope
      ? metadata.merging(focusStructureMetadata(scopeBoundary: true)) : metadata
  }
}

/// Whether the presentation is a new interaction domain or an extension of
/// its presenter. This is independent of whether it blocks background input.
package enum PresentationEnablementPolicy: Sendable {
  case inheritsPresenter
  case independent
}

package protocol PortalPresentationItem: Identifiable, Sendable where ID == String {
  var portalEntryID: PortalEntryID { get }
  var enablementPolicy: PresentationEnablementPolicy { get }
  var entryDismissObserver: (@MainActor @Sendable () -> Void)? { get }
}

extension PortalPresentationItem {
  package var enablementPolicy: PresentationEnablementPolicy { .inheritsPresenter }
}

package struct PromptPresentationItem: PortalPresentationItem {
  package var enablementPolicy: PresentationEnablementPolicy
  package var id: String
  package var portalEntryID: PortalEntryID
  package var title: String
  package var surface: PortalSurfacePresentation
  package var actionPayloads: [PortalAttachmentPayload]
  package var messagePayloads: [PortalAttachmentPayload]
  package var contentPayloads: [PortalAttachmentPayload]
  package var dismiss: @MainActor @Sendable () -> Void
  package var onDismiss: (@MainActor @Sendable () -> Void)?
  /// The dismissal an alert's or confirmation dialog's action row applies
  /// after each action runs; `nil` for every other surface.
  package var actionDismissal: PromptActionDismissal?

  package var entryDismissObserver: (@MainActor @Sendable () -> Void)? {
    onDismiss
  }

  package var semanticMetadata: SemanticMetadata {
    var metadata = surface.semanticMetadata
    if !title.isEmpty { metadata.accessibilityLabel = title }
    return metadata
  }

  @MainActor
  package init(
    id: String,
    portalEntryID: PortalEntryID? = nil,
    enablementPolicy: PresentationEnablementPolicy = .inheritsPresenter,
    title: String,
    surface: PreparedPortalSurface,
    actionPayloads: [PortalAttachmentPayload],
    messagePayloads: [PortalAttachmentPayload],
    contentPayloads: [PortalAttachmentPayload],
    dismiss: @escaping @MainActor @Sendable () -> Void,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    actionDismissal: PromptActionDismissal? = nil
  ) {
    let portalEntryID = portalEntryID ?? fallbackPortalEntryID(for: id)
    let edge = PortalAttachmentEdge(portalEntryID: portalEntryID)
    self.id = id
    self.portalEntryID = portalEntryID
    self.enablementPolicy = enablementPolicy
    self.title = title
    self.surface = surface.make(
      messagePayloads.contains { $0.hasDeclaredContent },
      actionPayloads.contains { $0.hasDeclaredContent })
    self.actionPayloads = actionPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.messagePayloads = messagePayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.contentPayloads = contentPayloads.map { $0.attachingEdgeIfMissing(edge) }
    self.dismiss = dismiss
    self.onDismiss = onDismiss
    self.actionDismissal = actionDismissal
  }
}

/// SwiftUI's prompt rule: every action of an alert or confirmation dialog
/// dismisses the prompt after the action runs. The prompt surface installs it
/// on its action row (`PromptActionPortalSurface`), and a `Button` there runs
/// its action through ``perform(_:)``. An action that changes the prompt's
/// source itself — it dismisses the prompt, presents a different item, or
/// writes a binding that reports its writes (a `@State` projection) — keeps
/// that outcome, so an action that re-presents still works (STUI-1309).
///
/// Equal for reuse per activation: the closures read the presentation's
/// binding when they run, so an earlier resolve's copy behaves the same.
package struct PromptActionDismissal: Sendable, Equatable {
  private struct Source {
    /// The presented activation: `"presented"` for a Boolean prompt, the
    /// item's ID for an item prompt, `nil` when nothing is presented.
    var activation: String?
    /// The binding's write identity, when its storage reports one.
    var writeIdentity: StateValueIdentity?
  }

  private let portalEntryID: PortalEntryID
  private let source: @MainActor @Sendable () -> Source
  private let dismiss: @MainActor @Sendable () -> Void

  @MainActor
  package init(
    isPresented: Binding<Bool>,
    portalEntryID: PortalEntryID,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.portalEntryID = portalEntryID
    source = {
      Source(
        activation: isPresented.wrappedValue ? "presented" : nil,
        writeIdentity: isPresented.valueIdentity?())
    }
    self.dismiss = dismiss
  }

  @MainActor
  package init<Item: Identifiable & Sendable>(
    item: Binding<Item?>,
    portalEntryID: PortalEntryID,
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.portalEntryID = portalEntryID
    source = {
      Source(
        activation: item.wrappedValue.map { String(reflecting: $0.id) },
        writeIdentity: item.valueIdentity?())
    }
    self.dismiss = dismiss
  }

  /// Runs `action`, then dismisses the prompt unless the action changed it.
  @MainActor
  package func perform(_ action: () -> Void) {
    let before = source()
    action()
    guard before.activation != nil else {
      return
    }
    let after = source()
    // The action dismissed the prompt or presented a different item.
    guard after.activation == before.activation else {
      return
    }
    // The action wrote the binding itself, for instance to re-present.
    if let original = before.writeIdentity, let written = after.writeIdentity,
      written !== original
    {
      return
    }
    dismiss()
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.portalEntryID == rhs.portalEntryID
  }
}

private enum PromptActionDismissalKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: PromptActionDismissal? = nil
}

extension EnvironmentValues {
  /// The prompt dismissal a `Button` in an alert's or confirmation dialog's
  /// action row applies after its action runs.
  package var promptActionDismissal: PromptActionDismissal? {
    get { self[PromptActionDismissalKey.self] }
    set { self[PromptActionDismissalKey.self] = newValue }
  }
}

package struct PopoverPresentationItem: PortalPresentationItem {
  package var id: String
  package var portalEntryID: PortalEntryID
  package var sourceIdentity: Identity
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var modalPolicy: PortalModalPolicy
  package var enablementPolicy: PresentationEnablementPolicy = .independent
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
  package var sourceEnvironmentValues: EnvironmentValues?
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
    sourceEnvironmentValues: EnvironmentValues? = nil,
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
    self.sourceEnvironmentValues = sourceEnvironmentValues
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
