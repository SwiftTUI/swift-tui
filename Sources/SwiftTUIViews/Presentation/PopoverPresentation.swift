public import SwiftTUICore

// `PopoverAttachmentAnchor` and its unit→cell `attachmentRect` resolution live
// in `PopoverAttachmentAnchor.swift`.

extension View {
  /// Presents a compact popover attached to this view.
  public func popover<PopoverContent: View>(
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content popoverContent: () -> PopoverContent
  ) -> some View {
    modifier(
      BuiltinPopoverPresentationModifier(
        isPresented: isPresented,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        popoverContent: popoverContent(),
        popoverContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a compact popover for the current optional item.
  public func popover<Item: Identifiable & Sendable, PopoverContent: View>(
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content popoverContent: @escaping @MainActor (Item) -> PopoverContent
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemPopoverPresentationModifier(
        item: item,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        popoverContent: popoverContent,
        popoverContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a lightweight tip as a source-attached popover.
  public func popoverTip<Tip: PopoverTip>(
    _ tip: Tip?,
    isPresented: Binding<Bool>? = nil,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    action: @escaping @MainActor @Sendable (PopoverTipAction) -> Void = { _ in }
  ) -> some View {
    modifier(
      PopoverTipModifier(
        tip: tip,
        isPresented: isPresented,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        action: action,
        actionAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }
}

package struct BuiltinPopoverPresentationModifier<PopoverContent: View>: PrimitiveViewModifier {
  package var isPresented: Binding<Bool>
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var popoverContent: PopoverContent
  package var popoverContentAuthoringContext: AuthoringContext?
  package var dismissAuthoringContext: AuthoringContext?
  package var onDismiss: (@MainActor @Sendable () -> Void)? = nil
  package var onDismissAuthoringContext: AuthoringContext? = nil

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    // Lever B for popovers: the `isPresented` read moves into the trigger
    // leaf so toggling spares the disjoint-sibling background. See
    // ``resolvePresentationModifier``.
    let isPresented = isPresented
    let attachmentAnchor = attachmentAnchor
    let arrowEdge = arrowEdge
    let popoverContent = popoverContent
    let popoverContentAuthoringContext = popoverContentAuthoringContext
    let dismissAuthoringContext = dismissAuthoringContext
    let onDismiss = presentationDismissObserver(
      onDismiss,
      authoringContext: onDismissAuthoringContext
    )
    let dismissInvalidator = context.invalidationProxy?.invalidator
    return resolvePresentationModifier(
      content: content,
      isPresented: isPresented,
      in: context
    ) { background, triggerIdentity in
      let sourceIdentity = background.identity
      let portalEntryID = presentationAttachment(for: background, token: "popover")
      let itemID = portalEntryID.description
      let item = popoverPresentationItem(
        id: itemID,
        portalEntryID: portalEntryID,
        sourceIdentity: sourceIdentity,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        modalPolicy: .disablesBaseInteraction,
        contentPayloads: withAuthoringContext(popoverContentAuthoringContext) {
          portalAttachmentDeclaredBuilderChildren(
            from: popoverContent,
            portalEntryID: portalEntryID,
            modalPolicy: .disablesBaseInteraction
          )
        },
        dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, triggerIdentity] in
          withAuthoringContext(dismissAuthoringContext) {
            isPresented.wrappedValue = false
          }
          requestPresentationDismissReconcile(
            dismissInvalidator,
            triggerIdentity: triggerIdentity
          )
        },
        onDismiss: onDismiss
      )
      return popoverDeclarationValue(item, sourceIdentity: sourceIdentity)
    }
  }
}
