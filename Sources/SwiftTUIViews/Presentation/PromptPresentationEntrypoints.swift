import SwiftTUICore

package struct PromptPresentationSpec: Sendable {
  package var token: String
  package var defaultDismissTitle: String
  package var prepareSurface: @MainActor @Sendable (ResolveContext) -> PreparedPortalSurface
  package var reconcile:
    @MainActor @Sendable (PresentationCoordinatorRegistry, Identity, PromptPresentationItem) -> Void
}

package func alertPromptPresentationSpec() -> PromptPresentationSpec {
  promptPresentationSpec(
    token: "alert", alignment: .center, accessibilityRole: .alert,
    defaultDismissTitle: "Dismiss", baseline: .init(),
    reconcile: { registry, identity, item in
      registry.alert.sync(sourceIdentity: identity, items: [item])
    })
}

package func confirmationDialogPromptPresentationSpec() -> PromptPresentationSpec {
  promptPresentationSpec(
    token: "confirmationDialog", alignment: .bottomLeading, accessibilityRole: .confirmationDialog,
    defaultDismissTitle: "Cancel",
    baseline: .init(
      headerTone: .accent, minimumWidth: 20, maximumWidth: nil,
      scrollMinimumHeight: 3, scrollIdealHeight: 4, scrollMaximumHeight: 6),
    reconcile: { registry, identity, item in
      registry.confirmationDialog.sync(sourceIdentity: identity, items: [item])
    })
}

private func promptPresentationSpec(
  token: String,
  alignment: Alignment,
  accessibilityRole: AccessibilityRole,
  defaultDismissTitle: String,
  baseline: PromptSurfaceStylePresentation,
  reconcile:
    @escaping @MainActor @Sendable (
      PresentationCoordinatorRegistry, Identity, PromptPresentationItem
    ) -> Void
) -> PromptPresentationSpec {
  .init(
    token: token, defaultDismissTitle: defaultDismissTitle,
    prepareSurface: { context in
      let style = context.environmentValues.promptStyle
      let terminalSize = context.environmentValues.terminalSize
      let prominence = context.environmentValues.controlProminence
      let environment = context.environmentValues.styleEnvironmentSnapshot
      let identity = context.identity
      return PreparedPortalSurface { hasMessage, hasActions in
        let resolved = style.presentation(
          for: .init(
            hasMessage: hasMessage, hasActions: hasActions, defaultPresentation: baseline,
            terminalSize: terminalSize, controlProminence: prominence, styleEnvironment: environment
          ))
        let presentation = StyleMisuse.validatedPresentation(
          resolved, problems: resolved.validationProblems, family: "PromptStyle",
          styleLabel: style.description, identity: identity,
          report: ImperativeRuntimeIssueQueue.record, fallback: { baseline })
        return PortalSurfacePresentation(
          alignment: alignment, backdropOpacity: presentation.backdropOpacity,
          hostInsets: .init(horizontal: 1, vertical: 1), accessibilityRole: accessibilityRole
        ) { item in
          PromptActionPortalSurface(item: item, presentation: presentation)
        }
      }
    }, reconcile: reconcile)
}

package func menuPromptPresentationSpec(
  presentation: AnchoredSurfaceStylePresentation = .init()
) -> PromptPresentationSpec {
  .init(
    token: "menu", defaultDismissTitle: "Close",
    prepareSurface: { _ in
      PreparedPortalSurface { _, _ in
        anchoredSurfacePresentation(
          presentation, accessibilityRole: .menu,
          hostInsets: .init(top: 0, leading: 1, bottom: 0, trailing: 0))
      }
    },
    reconcile: { registry, identity, item in
      registry.menu.sync(sourceIdentity: identity, items: [item])
    })
}

package func sheetPromptPresentationSpec(
  backdropOpacity: Double = 0,
  container: SheetSurfaceContainer = .standard
) -> PromptPresentationSpec {
  let baseline = SheetSurfaceStylePresentation(
    container: container, backdropOpacity: backdropOpacity,
    minimumWidth: container == .dropdown ? 0 : 20)
  return .init(
    token: "sheet", defaultDismissTitle: "Close",
    prepareSurface: { context in
      let presentation = context.resolvedSheetPresentation(baseline: baseline)
      return PreparedPortalSurface { _, _ in sheetSurfacePresentation(presentation) }
    },
    reconcile: { registry, identity, item in
      registry.sheet.sync(sourceIdentity: identity, items: [item])
    })
}

/// Palette declarations keep their fixed dropdown surface until their own
/// data-driven style supplies its presentation; SheetStyle does not govern them.
package func palettePromptPresentationSpec() -> PromptPresentationSpec {
  .init(
    token: "sheet", defaultDismissTitle: "Close",
    prepareSurface: { _ in
      PreparedPortalSurface { _, _ in
        PortalSurfacePresentation(alignment: .topLeading, accessibilityRole: .sheet) { item in
          DropdownContentPortalSurface(
            item: item, presentation: .init(container: .dropdown, minimumWidth: 0))
        }
      }
    },
    reconcile: { registry, identity, item in
      registry.sheet.sync(sourceIdentity: identity, items: [item])
    })
}

@MainActor
private func sheetSurfacePresentation(_ presentation: SheetSurfaceStylePresentation)
  -> PortalSurfacePresentation
{
  switch presentation.container {
  case .standard:
    PortalSurfacePresentation(
      alignment: .center, backdropOpacity: presentation.backdropOpacity,
      hostInsets: .init(horizontal: 1, vertical: 1), accessibilityRole: .sheet
    ) { item in StandardContentPortalSurface(item: item, presentation: presentation) }
  case .dropdown:
    PortalSurfacePresentation(
      alignment: .topLeading, backdropOpacity: presentation.backdropOpacity,
      accessibilityRole: .sheet
    ) { item in DropdownContentPortalSurface(item: item, presentation: presentation) }
  }
}

package func fullScreenCoverPromptPresentationSpec() -> PromptPresentationSpec {
  .init(
    token: "fullScreenCover", defaultDismissTitle: "Close",
    prepareSurface: { context in
      let baseline = FullScreenSurfaceStylePresentation()
      let style = context.environmentValues.fullScreenCoverStyle
      let resolved = style.presentation(
        for: .init(
          defaultPresentation: baseline, terminalSize: context.environmentValues.terminalSize,
          controlProminence: context.environmentValues.controlProminence,
          styleEnvironment: context.environmentValues.styleEnvironmentSnapshot))
      let presentation = StyleMisuse.validatedPresentation(
        resolved, problems: resolved.validationProblems, family: "FullScreenCoverStyle",
        styleLabel: style.description, identity: context.identity,
        report: ImperativeRuntimeIssueQueue.record, fallback: { baseline })
      return PreparedPortalSurface { _, _ in
        PortalSurfacePresentation(alignment: .topLeading, accessibilityRole: .sheet) { item in
          FullScreenContentPortalSurface(item: item, presentation: presentation)
        }
      }
    },
    reconcile: { registry, identity, item in
      registry.sheet.sync(sourceIdentity: identity, items: [item])
    })
}

@MainActor
package func anchoredSurfacePresentation(
  _ presentation: AnchoredSurfaceStylePresentation,
  accessibilityRole: AccessibilityRole,
  createsFocusScope: Bool = true,
  hostInsets: EdgeInsets = .zero
) -> PortalSurfacePresentation {
  PortalSurfacePresentation(
    alignment: .topLeading, hostInsets: hostInsets, isIntrinsic: true,
    accessibilityRole: accessibilityRole, createsFocusScope: createsFocusScope
  ) { item in
    AnchoredContentPortalSurface(
      content: VStack(alignment: .leading, spacing: 0) {
        PortalAttachmentSequenceView(payloads: item.contentPayloads)
      }, presentation: presentation, semanticMetadata: item.surface.semanticMetadata)
  }
}

extension View {
  /// Presents an alert with a default dismiss action.
  public func alert<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    let spec = alertPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makePortalAttachmentAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents an alert with custom actions and message content.
  public func alert<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: alertPromptPresentationSpec(),
        actions: actions(),
        message: message(),
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents an alert for the current optional item with a default dismiss action.
  public func alert<S: StringProtocol, Item: Identifiable & Sendable>(
    _ title: S,
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View where Item.ID: Sendable {
    let spec = alertPromptPresentationSpec()
    let dismissAuthoringContext = makePortalAttachmentAuthoringContext()
    return modifier(
      BuiltinItemPromptPresentationModifier(
        title: String(title),
        item: item,
        spec: spec,
        actions: { _ in
          defaultItemPresentationActions(
            defaultDismissTitle: spec.defaultDismissTitle,
            item: item,
            dismissAuthoringContext: dismissAuthoringContext
          )
        },
        message: { _ in EmptyView() },
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: dismissAuthoringContext,
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents an alert whose actions and message receive the current optional item.
  public func alert<
    S: StringProtocol,
    Item: Identifiable & Sendable,
    Actions: View,
    Message: View
  >(
    _ title: S,
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder actions: @escaping @MainActor (Item) -> Actions,
    @ViewBuilder message: @escaping @MainActor (Item) -> Message
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemPromptPresentationModifier(
        title: String(title),
        item: item,
        spec: alertPromptPresentationSpec(),
        actions: actions,
        message: message,
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog with a default dismiss action.
  public func confirmationDialog<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    let spec = confirmationDialogPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makePortalAttachmentAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog with custom actions and message content.
  public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: confirmationDialogPromptPresentationSpec(),
        actions: actions(),
        message: message(),
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog for the current optional item.
  public func confirmationDialog<S: StringProtocol, Item: Identifiable & Sendable>(
    _ title: S,
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View where Item.ID: Sendable {
    let spec = confirmationDialogPromptPresentationSpec()
    let dismissAuthoringContext = makePortalAttachmentAuthoringContext()
    return modifier(
      BuiltinItemPromptPresentationModifier(
        title: String(title),
        item: item,
        spec: spec,
        actions: { _ in
          defaultItemPresentationActions(
            defaultDismissTitle: spec.defaultDismissTitle,
            item: item,
            dismissAuthoringContext: dismissAuthoringContext
          )
        },
        message: { _ in EmptyView() },
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: dismissAuthoringContext,
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog whose builders receive the current item.
  public func confirmationDialog<
    S: StringProtocol,
    Item: Identifiable & Sendable,
    Actions: View,
    Message: View
  >(
    _ title: S,
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder actions: @escaping @MainActor (Item) -> Actions,
    @ViewBuilder message: @escaping @MainActor (Item) -> Message
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemPromptPresentationModifier(
        title: String(title),
        item: item,
        spec: confirmationDialogPromptPresentationSpec(),
        actions: actions,
        message: message,
        actionsAuthoringContext: makePortalAttachmentAuthoringContext(),
        messageAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents custom sheet content without a title.
  public func sheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: "",
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents titled custom sheet content.
  public func sheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents custom sheet content for the current optional item.
  public func sheet<Item: Identifiable & Sendable, SheetContent: View>(
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content sheetContent: @escaping @MainActor (Item) -> SheetContent
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemSheetPresentationModifier(
        title: "",
        item: item,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent,
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents titled custom sheet content for the current optional item.
  public func sheet<
    S: StringProtocol,
    Item: Identifiable & Sendable,
    SheetContent: View
  >(
    _ title: S,
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content sheetContent: @escaping @MainActor (Item) -> SheetContent
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemSheetPresentationModifier(
        title: String(title),
        item: item,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent,
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents content that occupies the full terminal surface.
  public func fullScreenCover<CoverContent: View>(
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content coverContent: () -> CoverContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: "",
        isPresented: isPresented,
        spec: fullScreenCoverPromptPresentationSpec(),
        sheetContent: coverContent(),
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

  /// Presents full-screen content for the current optional item.
  public func fullScreenCover<
    Item: Identifiable & Sendable,
    CoverContent: View
  >(
    item: Binding<Item?>,
    onDismiss: (@MainActor @Sendable () -> Void)? = nil,
    @ViewBuilder content coverContent: @escaping @MainActor (Item) -> CoverContent
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemSheetPresentationModifier(
        title: "",
        item: item,
        spec: fullScreenCoverPromptPresentationSpec(),
        sheetContent: coverContent,
        sheetContentAuthoringContext: makePortalAttachmentAuthoringContext(),
        dismissAuthoringContext: makePortalAttachmentAuthoringContext(),
        onDismiss: onDismiss,
        onDismissAuthoringContext: makePortalAttachmentAuthoringContext()
      )
    )
  }

}

@MainActor
private func defaultPresentationActions(
  defaultDismissTitle: String,
  isPresented: Binding<Bool>,
  dismissAuthoringContext: AuthoringContext?
) -> Button<Text> {
  Button(
    defaultDismissTitle,
    action: {
      withAuthoringContext(dismissAuthoringContext) {
        isPresented.wrappedValue = false
      }
    }
  )
}

@MainActor
private func defaultItemPresentationActions<Item>(
  defaultDismissTitle: String,
  item: Binding<Item?>,
  dismissAuthoringContext: AuthoringContext?
) -> Button<Text> {
  Button(
    defaultDismissTitle,
    action: {
      withAuthoringContext(dismissAuthoringContext) {
        item.wrappedValue = nil
      }
    }
  )
}
