package import Core

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
      presentationRole: .alert,
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
      presentationRole: .confirmationDialog,
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
    }
  let minWidth: Int =
    switch chrome {
    case .surface: 20
    case .dropdown: 0
    }
  return PromptPresentationSpec(
    token: "sheet",
    descriptor: .init(
      alignment: alignment,
      presentationRole: .sheet,
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
          isPresented: isPresented
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

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
        messageAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

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
          isPresented: isPresented
        ),
        message: EmptyView(),
        actionsAuthoringContext: makeDeferredAuthoringContext(),
        messageAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

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
        messageAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

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
        sheetContentAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

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
        sheetContentAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents `content` as a full-width, top-aligned dropdown banner
  /// with a single soft bottom divider and no side or top border —
  /// suited to command palettes and similar chrome that should read as
  /// part of the window itself rather than a floating card.
  ///
  /// Semantically a sheet (routes through the sheet presentation
  /// registry and obeys the same Escape-dismissal rules), distinguished
  /// only by its visual chrome.
  public func paletteSheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    modifier(
      BuiltinSheetPresentationModifier(
        title: String(title),
        isPresented: isPresented,
        spec: sheetPromptPresentationSpec(chrome: .dropdown),
        sheetContent: sheetContent(),
        sheetContentAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }
}

@MainActor
private func defaultPresentationActions(
  defaultDismissTitle: String,
  isPresented: Binding<Bool>
) -> Button<Text> {
  Button(
    defaultDismissTitle,
    action: {
      isPresented.wrappedValue = false
    }
  )
}

public struct BuiltinPromptPresentationModifier<Actions: View, Message: View>:
  PrimitiveViewModifier
{
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var actions: Actions
  var message: Message
  var actionsAuthoringContext: AuthoringContext?
  var messageAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: withAuthoringContext(actionsAuthoringContext) {
        deferredDeclaredBuilderChildren(from: actions)
      },
      messagePayloads: withAuthoringContext(messageAuthoringContext) {
        deferredDeclaredBuilderChildren(from: message)
      },
      contentPayloads: [],
      dismiss: { [isPresented] in
        isPresented.wrappedValue = false
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

public struct BuiltinSheetPresentationModifier<SheetContent: View>: PrimitiveViewModifier {
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var sheetContent: SheetContent
  var sheetContentAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let item = PromptPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: spec.token
      ),
      title: title,
      descriptor: spec.descriptor,
      actionPayloads: [],
      messagePayloads: [],
      contentPayloads: withAuthoringContext(sheetContentAuthoringContext) {
        deferredDeclaredBuilderChildren(from: sheetContent)
      },
      dismiss: { [isPresented] in
        isPresented.wrappedValue = false
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            spec.reconcile(
              registry,
              sourceIdentity,
              item
            )
          }
        ]
      )
    )
    return [node]
  }
}

package struct HostedPromptPresentation: View {
  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  package var body: some View {
    // Dropdown chrome lands flush against the window edges; surface
    // chrome floats with a 1-cell inset so the stroked box never kisses
    // the terminal edge.
    let insetEdges: EdgeInsets =
      switch item.descriptor.chrome {
      case .surface: .init(top: 1, leading: 1, bottom: 1, trailing: 1)
      case .dropdown: .init(top: 0, leading: 0, bottom: 0, trailing: 0)
      }
    return ZStack(alignment: .topLeading) {
      if item.descriptor.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(item.descriptor.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      PromptPresentationSurface(item: item)
        .padding(insetEdges)
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: item.descriptor.alignment
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// The root view of a presented sheet/alert/confirmation-dialog
/// subtree.
///
/// `PromptPresentationSurface` is the presented content root: when a
/// `.sheet(...)`, `.alert(...)`, or `.confirmationDialog(...)` is
/// active, this view appears as the root of that presentation's
/// subtree in the rendered tree, wrapped in the presentation host
/// overlay. Its resolved node carries `focusScopeBoundary: true` via
/// the `.focusScope()` modifier applied in its body, so every focus
/// region emitted underneath a presentation carries the
/// presentation's identity on its `scopePath`.
///
/// Conforming to `ActionScope` makes the presentation a first-class
/// scope in the `ActionScope` world: commands scoped to the
/// presentation become active exactly when the presentation's scope
/// identity is on the focus chain.
package struct PromptPresentationSurface: View, ActionScope {
  package typealias ID = String

  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  /// The presentation's identity is the item's attachment id — a
  /// stable `String` derived from the source identity and the
  /// presentation token (see `presentationAttachmentID`).
  package nonisolated var id: String {
    item.id
  }

  package var body: some View {

    let content = VStack(alignment: .leading, spacing: 0) {
      presentationHeader
      switch item.descriptor.bodyMode {
      case .contentOnly:
        contentBody
      case .messageAndActions:
        messageAndActionBody
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))

    switch item.descriptor.chrome {
    case .surface:
      content
        .background {
          RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(.terminalSurfaceBackground)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
            .terminalBorder(.accent),
            style: .presentationChrome
          )
        }
        .frame(
          minWidth: .finite(item.descriptor.minWidth),
          maxWidth: maximumWidth,
          alignment: .leading
        )
        .focusScope()
        .semanticMetadata(
          .init(
            presentationRole: item.descriptor.presentationRole
          )
        )
    case .dropdown:
      // Full-width, top-aligned strip. No side or top border — a single
      // soft bottom divider reads as a shadow under the content.
      content
        .frame(
          maxWidth: .infinity,
          alignment: .topLeading
        )
        .background {
          Rectangle().fill(.terminalSurfaceBackground)
        }
        .overlay(alignment: .bottom) {
          Divider()
            .foregroundStyle(.separator)
            .drawMetadata(.init(opacity: 0.6))
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .focusScope()
        .semanticMetadata(
          .init(
            presentationRole: item.descriptor.presentationRole
          )
        )
    }
  }

  private var maximumWidth: ProposedDimension {
    if let maxWidth = item.descriptor.maxWidth {
      return .finite(maxWidth)
    }
    return .infinity
  }

  private var presentationHeader: some View {
    HStack(alignment: .center, spacing: 1) {
      if !item.title.isEmpty {
        Text(item.title)
          .bold()
      }
      Spacer(minLength: 0)
      Button("×", role: .close, action: item.dismiss)
        .buttonStyle(.borderedProminent)
    }
    .frame(height: 1, alignment: .leading)
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(item.descriptor.headerTone, isSelected: true))
  }

  private var messageAndActionBody: some View {
    Group {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if !item.messagePayloads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              DeferredPayloadGroupView(
                kindName: "PresentationMessage",
                payloads: item.messagePayloads
              )
            }
            .padding(.init(horizontal: 1, vertical: 1))
          }
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(item.descriptor.scrollMinHeight),
        idealHeight: .finite(item.descriptor.scrollIdealHeight),
        maxHeight: .finite(item.descriptor.scrollMaxHeight),
        alignment: .topLeading
      )
      presentationActions
    }
  }

  private var contentBody: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        DeferredPayloadGroupView(
          kindName: "PresentationContent",
          payloads: item.contentPayloads
        )
      }
      .padding(.init(horizontal: 1, vertical: 1))
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(item.descriptor.scrollMinHeight),
      idealHeight: .finite(item.descriptor.scrollIdealHeight),
      maxHeight: .finite(item.descriptor.scrollMaxHeight),
      alignment: .topLeading
    )
  }

  private var presentationActions: some View {
    HStack(spacing: 1) {
      ForEach(item.actionPayloads.indices, id: \.self) { index in
        DeferredPayloadView(payload: item.actionPayloads[index])
          .fixedSize()
      }
    }
    .fixedSize()
    .padding(.init(horizontal: 1, vertical: 0))
  }

}

// MARK: - Toast / Transient Notification System

/// Visual style for toast notifications.
public enum ToastStyle: Equatable, Sendable {
  case info
  case success
  case warning
  case danger

  var tone: TerminalTone {
    switch self {
    case .info: .info
    case .success: .success
    case .warning: .warning
    case .danger: .danger
    }
  }

  var icon: String {
    switch self {
    case .info: "ℹ"
    case .success: "✓"
    case .warning: "⚠"
    case .danger: "✗"
    }
  }
}

extension View {
  /// Displays a transient notification bar that auto-dismisses.
  public func toast<S: StringProtocol>(
    _ message: S,
    isPresented: Binding<Bool>,
    style: ToastStyle = .info,
    duration: Double? = 3.0
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: Text(String(message))
      )
    )
  }

  /// Displays a transient notification with custom content that auto-dismisses.
  public func toast<ToastContent: View>(
    isPresented: Binding<Bool>,
    style: ToastStyle = .info,
    duration: Double? = 3.0,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    modifier(
      ToastModifier(
        isPresented: isPresented,
        style: style,
        duration: duration,
        toastContent: toastContent()
      )
    )
  }
}

public struct ToastModifier<ToastContent: View>: PrimitiveViewModifier {
  var isPresented: Binding<Bool>
  var style: ToastStyle
  var duration: Double?
  var toastContent: ToastContent

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let item = ToastPresentationItem(
      id: presentationAttachmentID(
        for: sourceIdentity,
        token: "toast"
      ),
      contentPayloads: deferredDeclaredBuilderChildren(from: toastContent),
      style: style,
      duration: duration,
      dismiss: { [isPresented] in
        isPresented.wrappedValue = false
      }
    )

    node.preferenceValues.merge(
      PresentationCoordinatorDeclarationPreferenceKey.self,
      value: .init(
        declarations: [
          .init(sourceIdentity: sourceIdentity) { registry in
            registry.toast.sync(
              sourceIdentity: sourceIdentity,
              items: [item]
            )
          }
        ]
      )
    )
    return [node]
  }
}

package struct ToastCoordinatorBodyView: View {
  package var items: [ToastPresentationItem]

  package init(
    items: [ToastPresentationItem]
  ) {
    self.items = items
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 1) {
        ForEach(items) { item in
          ToastPresentationView(item: item)
        }
      }
      .padding(.bottom, 1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .allowsHitTesting(false)
  }
}

private struct ToastPresentationView: View {
  var item: ToastPresentationItem

  var body: some View {
    HStack(alignment: .center, spacing: 1) {
      Text(item.style.icon)
        .foregroundStyle(.terminalAccent(item.style.tone))
      VStack {
        DeferredPayloadGroupView(
          kindName: "ToastContent",
          payloads: item.contentPayloads
        )
      }
    }
    .padding(1)
    .background {
      Rectangle().fill(AnyShapeStyle(.terminalSurfaceBackground))
    }
    .overlay {
      Rectangle().chromeStrokeBorder(
        .terminalBorder(item.style.tone)
      )
    }
    .frame(
      minWidth: .finite(10),
      maxWidth: .finite(60),
      minHeight: .finite(3),
      idealHeight: .finite(3),
      maxHeight: .finite(5),
      alignment: .leading
    )
    .task {
      guard let duration = item.duration, duration > 0 else {
        return
      }
      try? await Task.sleep(for: .seconds(duration))
      item.dismiss()
    }
  }
}
