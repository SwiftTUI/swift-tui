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
  backdropOpacity: Double = 0
) -> PromptPresentationSpec {
  PromptPresentationSpec(
    token: "sheet",
    descriptor: .init(
      alignment: .center,
      presentationRole: .sheet,
      backdropOpacity: backdropOpacity,
      defaultDismissTitle: "Close",
      headerTone: .accent,
      minWidth: 20,
      scrollMinHeight: 4,
      scrollIdealHeight: 12,
      scrollMaxHeight: 20,
      bodyMode: .contentOnly
    ),
    reconcile: { registry, sourceIdentity, item in
      registry.sheet.sync(
        sourceIdentity: sourceIdentity,
        items: [item]
      )
    }
  )
}

package func commandPalettePromptPresentationSpec() -> PromptPresentationSpec {
  let baseSpec = sheetPromptPresentationSpec(backdropOpacity: 0.7)
  return PromptPresentationSpec(
    token: "commandPalette",
    descriptor: baseSpec.descriptor,
    reconcile: { registry, sourceIdentity, item in
      registry.commandPalette.sync(
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
    return BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      spec: spec,
      actions: defaultPresentationActions(
        defaultDismissTitle: spec.descriptor.defaultDismissTitle,
        isPresented: isPresented
      ),
      message: EmptyView()
    )
  }

  public func alert<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      spec: alertPromptPresentationSpec(),
      actions: actions(),
      message: message()
    )
  }

  public func confirmationDialog<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    let spec = confirmationDialogPromptPresentationSpec()
    return BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      spec: spec,
      actions: defaultPresentationActions(
        defaultDismissTitle: spec.descriptor.defaultDismissTitle,
        isPresented: isPresented
      ),
      message: EmptyView()
    )
  }

  public func confirmationDialog<S: StringProtocol, Actions: View, Message: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      spec: confirmationDialogPromptPresentationSpec(),
      actions: actions(),
      message: message()
    )
  }

  public func sheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    BuiltinSheetPresentationModifier(
      content: self,
      title: "",
      isPresented: isPresented,
      spec: sheetPromptPresentationSpec(),
      sheetContent: sheetContent()
    )
  }

  public func sheet<S: StringProtocol, SheetContent: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    @ViewBuilder content sheetContent: () -> SheetContent
  ) -> some View {
    BuiltinSheetPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      spec: sheetPromptPresentationSpec(),
      sheetContent: sheetContent()
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

private struct BuiltinPromptPresentationModifier<
  Content: View, Actions: View,
  Message: View
>: View, ResolvableView {
  var content: Content
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var actions: Actions
  var message: Message

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
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
      actionPayloads: deferredDeclaredBuilderChildren(from: actions),
      messagePayloads: deferredDeclaredBuilderChildren(from: message),
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

private struct BuiltinSheetPresentationModifier<Content: View, SheetContent: View>: View,
  ResolvableView
{
  var content: Content
  var title: String
  var isPresented: Binding<Bool>
  var spec: PromptPresentationSpec
  var sheetContent: SheetContent

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
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
      contentPayloads: deferredDeclaredBuilderChildren(from: sheetContent),
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
    ZStack(alignment: .topLeading) {
      if item.descriptor.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(item.descriptor.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      PromptPresentationSurface(item: item)
        .padding(
          .init(
            top: 1,
            leading: 1,
            bottom: 1,
            trailing: 1
          )
        )
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: item.descriptor.alignment
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onKeyPress(.escape) {
      item.dismiss()
      return .handled
    }
  }
}

package struct PromptPresentationSurface: View {
  package var item: PromptPresentationItem

  package init(
    item: PromptPresentationItem
  ) {
    self.item = item
  }

  package var body: some View {
    let surfaceBackground = AnyShapeStyle(.terminalSurfaceBackground)

    VStack(alignment: .leading, spacing: 0) {
      presentationHeader
      switch item.descriptor.bodyMode {
      case .contentOnly:
        contentBody
      case .messageAndActions:
        messageAndActionBody
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))
    .background {
      RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(surfaceBackground)
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
    ToastModifier(
      content: self,
      isPresented: isPresented,
      style: style,
      duration: duration,
      toastContent: Text(String(message))
    )
  }

  /// Displays a transient notification with custom content that auto-dismisses.
  public func toast<ToastContent: View>(
    isPresented: Binding<Bool>,
    style: ToastStyle = .info,
    duration: Double? = 3.0,
    @ViewBuilder content toastContent: () -> ToastContent
  ) -> some View {
    ToastModifier(
      content: self,
      isPresented: isPresented,
      style: style,
      duration: duration,
      toastContent: toastContent()
    )
  }
}

private struct ToastModifier<Content: View, ToastContent: View>: View,
  ResolvableView
{
  var content: Content
  var isPresented: Binding<Bool>
  var style: ToastStyle
  var duration: Double?
  var toastContent: ToastContent

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
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
