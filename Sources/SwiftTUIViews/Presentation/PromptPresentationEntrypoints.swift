package import SwiftTUICore

package struct PromptPresentationSpec: Sendable {
  package var token: String
  package var descriptor: PromptPresentationDescriptor
  package var reconcile:
    @MainActor @Sendable (
      PresentationCoordinatorRegistry,
      Identity,
      PromptPresentationItem
    ) -> Void

  package init(
    token: String,
    descriptor: PromptPresentationDescriptor,
    reconcile:
      @escaping @MainActor @Sendable (
        PresentationCoordinatorRegistry,
        Identity,
        PromptPresentationItem
      ) -> Void
  ) {
    self.token = token
    self.descriptor = descriptor
    self.reconcile = reconcile
  }
}

package func alertPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "alert",
    descriptor: .init(
      alignment: .center,
      accessibilityRole: .alert,
      backdropOpacity: 0,
      defaultDismissTitle: "Dismiss",
      headerTone: .neutral,
      minWidth: 24,
      maxWidth: 48,
      scrollMinHeight: 2,
      scrollIdealHeight: 6,
      scrollMaxHeight: 10,
      bodyMode: .messageAndActions
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.alert.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

package func confirmationDialogPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "confirmationDialog",
    descriptor: .init(
      alignment: .bottomLeading,
      accessibilityRole: .confirmationDialog,
      backdropOpacity: 0,
      defaultDismissTitle: "Cancel",
      headerTone: .accent,
      minWidth: 20,
      scrollMinHeight: 3,
      scrollIdealHeight: 4,
      scrollMaxHeight: 6,
      bodyMode: .messageAndActions
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.confirmationDialog.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

/// Spec for `Menu`'s expanded content. Menus use a dedicated non-modal
/// portal entry with a unique `"menu"` token (so menu attachment IDs never
/// collide with sheet attachment IDs on the same source identity) and `.menu`
/// chrome (so the rendering surface is a compact, intrinsic-width bordered box
/// with no header).
package func menuPromptPresentationSpec() -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "menu",
    descriptor: .init(
      alignment: .topLeading,
      accessibilityRole: .menu,
      backdropOpacity: 0,
      defaultDismissTitle: "Close",
      headerTone: .accent,
      minWidth: 0,
      // Menus auto-size to content; the scroll bounds below act only as
      // a safety cap if a menu's content grows past the visible area.
      scrollMinHeight: 1,
      scrollIdealHeight: 8,
      scrollMaxHeight: 32,
      bodyMode: .contentOnly,
      chrome: .menu,
      contentSizing: .intrinsic
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.menu.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

package func sheetPromptPresentationSpec(
  backdropOpacity: Double = 0,
  chrome: PresentationChrome = .surface
) -> PromptPresentationSpec {
  // Dropdown-chromed sheets want to land flush against the window
  // edge (top, full width) rather than floating centered; override
  // the layout defaults so callers don't have to restate them.
  let alignment: Alignment =
    switch chrome {
    case .surface: .center
    case .dropdown: .topLeading
    // .menu is dispatched through `menuPromptPresentationSpec()`; if a
    // caller manually plumbs it through this sheet builder, fall back
    // to the dropdown-flavored top-leading anchoring.
    case .menu: .topLeading
    }
  let minWidth: Int =
    switch chrome {
    case .surface: 20
    case .dropdown: 0
    case .menu: 0
    }
  return PromptPresentationSpec(
    token: "sheet",
    descriptor: .init(
      alignment: alignment,
      accessibilityRole: .sheet,
      backdropOpacity: backdropOpacity,
      defaultDismissTitle: "Close",
      headerTone: .accent,
      minWidth: minWidth,
      scrollMinHeight: 4,
      scrollIdealHeight: 12,
      scrollMaxHeight: 20,
      bodyMode: .contentOnly,
      chrome: chrome
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.sheet.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

extension View {
  /// Presents an alert with a default dismiss action.
  public func alert<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    let spec = alertPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.descriptor.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makeDeferredAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents an alert with custom actions and message content.
  public func alert<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
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
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog with a default dismiss action.
  public func confirmationDialog<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    let spec = confirmationDialogPromptPresentationSpec()
    return modifier(
      BuiltinPromptPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: spec,
        actions: defaultPresentationActions(
          defaultDismissTitle: spec.descriptor.defaultDismissTitle,
          isPresented: isPresented,
          dismissAuthoringContext: makeDeferredAuthoringContext()
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents a confirmation dialog with custom actions and message content.
  public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
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
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents custom sheet content without a title.
  public func sheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: "",
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents titled custom sheet content.
  public func sheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
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
