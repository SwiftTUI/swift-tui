package import Core

package enum BuiltinPromptPresentationKind: Equatable, Sendable {
  case alert
  case confirmationDialog
  case sheet

  var alignment: Alignment {
    switch self {
    case .alert:
      .center
    case .confirmationDialog:
      .bottomLeading
    case .sheet:
      .center
    }
  }

  var family: PresentationFamilyID {
    switch self {
    case .alert:
      .alert
    case .confirmationDialog:
      .confirmationDialog
    case .sheet:
      .sheet
    }
  }

  var presentationRole: PresentationRole {
    switch self {
    case .alert:
      .alert
    case .confirmationDialog:
      .confirmationDialog
    case .sheet:
      .sheet
    }
  }

  var defaultDismissTitle: String {
    switch self {
    case .alert:
      "Dismiss"
    case .confirmationDialog:
      "Cancel"
    case .sheet:
      "Close"
    }
  }

  var usesContentPresentation: Bool {
    switch self {
    case .alert, .confirmationDialog:
      false
    case .sheet:
      true
    }
  }

  var requestToken: String {
    family.rawValue
  }
}

extension View {
  public func alert<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      kind: .alert,
      actions: defaultPresentationActions(
        kind: .alert,
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
      kind: .alert,
      actions: actions(),
      message: message()
    )
  }

  public func confirmationDialog<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    BuiltinPromptPresentationModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      kind: .confirmationDialog,
      actions: defaultPresentationActions(
        kind: .confirmationDialog,
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
      kind: .confirmationDialog,
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
      sheetContent: sheetContent()
    )
  }
}

@MainActor
private func defaultPresentationActions(
  kind: BuiltinPromptPresentationKind,
  isPresented: Binding<Bool>
) -> Button<Text> {
  Button(
    kind.defaultDismissTitle,
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
  var kind: BuiltinPromptPresentationKind
  var actions: Actions
  var message: Message

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    node.preferenceValues.merge(
      PresentationCoordinatorPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            requestID: .init(
              attachmentIdentity: node.identity,
              family: kind.family,
              token: kind.requestToken
            ),
            attachmentIdentity: node.identity,
            family: kind.family,
            priority: 0,
            surfacePayload: DeferredViewPayload {
              BuiltinHostedPromptPresentation(
                title: title,
                kind: kind,
                backdropOpacity: 0,
                actionPayloads: deferredDeclaredBuilderChildren(from: actions),
                messagePayloads: deferredDeclaredBuilderChildren(from: message),
                contentPayloads: [],
                dismiss: { [isPresented] in
                  isPresented.wrappedValue = false
                }
              )
            }
          )
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
  var sheetContent: SheetContent

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    node.preferenceValues.merge(
      PresentationCoordinatorPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            requestID: .init(
              attachmentIdentity: node.identity,
              family: PresentationFamilyID.sheet,
              token: BuiltinPromptPresentationKind.sheet.requestToken
            ),
            attachmentIdentity: node.identity,
            family: .sheet,
            priority: 0,
            surfacePayload: DeferredViewPayload {
              BuiltinHostedPromptPresentation(
                title: title,
                kind: .sheet,
                backdropOpacity: 0,
                actionPayloads: [],
                messagePayloads: [],
                contentPayloads: deferredDeclaredBuilderChildren(from: sheetContent),
                dismiss: { [isPresented] in
                  isPresented.wrappedValue = false
                }
              )
            }
          )
        ]
      )
    )
    return [node]
  }
}

package struct BuiltinHostedPromptPresentation: View {
  package var title: String
  package var kind: BuiltinPromptPresentationKind
  package var backdropOpacity: Double
  package var actionPayloads: [DeferredViewPayload]
  package var messagePayloads: [DeferredViewPayload]
  package var contentPayloads: [DeferredViewPayload]
  package var dismiss: @MainActor @Sendable () -> Void

  package init(
    title: String,
    kind: BuiltinPromptPresentationKind,
    backdropOpacity: Double,
    actionPayloads: [DeferredViewPayload],
    messagePayloads: [DeferredViewPayload],
    contentPayloads: [DeferredViewPayload],
    dismiss: @escaping @MainActor @Sendable () -> Void
  ) {
    self.title = title
    self.kind = kind
    self.backdropOpacity = backdropOpacity
    self.actionPayloads = actionPayloads
    self.messagePayloads = messagePayloads
    self.contentPayloads = contentPayloads
    self.dismiss = dismiss
  }

  package var body: some View {
    ZStack(alignment: .topLeading) {
      if backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      BuiltinPromptPresentationSurface(
        title: title,
        kind: kind,
        actionPayloads: actionPayloads,
        messagePayloads: messagePayloads,
        contentPayloads: contentPayloads,
        dismiss: dismiss
      )
      .padding(
        .init(
          top: 1,
          leading: 1,
          bottom: 1,
          trailing: 1
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: kind.alignment)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onKeyPress(.escape) {
      dismiss()
      return .handled
    }
  }
}

private struct BuiltinPromptPresentationSurface: View {
  var title: String
  var kind: BuiltinPromptPresentationKind
  var actionPayloads: [DeferredViewPayload]
  var messagePayloads: [DeferredViewPayload]
  var contentPayloads: [DeferredViewPayload]
  var dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      presentationHeader
      if kind.usesContentPresentation {
        sheetBody
      } else {
        alertDialogBody
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))
    .background {
      RoundedRectangle(cornerRadius: 1).chromeFill(.terminalSurfaceBackground)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
        .terminalBorder(.accent)
      )
    }
    .frame(
      minWidth: .finite(kind == .alert ? 24 : 20),
      maxWidth: kind == .alert ? .finite(48) : .infinity,
      alignment: .leading
    )
    .focusScope()
    .semanticMetadata(
      .init(
        presentationRole: kind.presentationRole
      )
    )
  }

  private var presentationHeader: some View {
    HStack(alignment: .center, spacing: 1) {
      if !title.isEmpty {
        Text(title)
          .bold()
      }
      Spacer(minLength: 0)
      Button("×", role: .close, action: dismiss)
        .buttonStyle(.borderedProminent)
    }
    .frame(height: 1, alignment: .leading)
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(kind == .alert ? .neutral : .accent, isSelected: true))
  }

  private var alertDialogBody: some View {
    Group {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if !messagePayloads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              DeferredPayloadGroupView(
                kindName: "PresentationMessage",
                payloads: messagePayloads
              )
            }
            .padding(.init(horizontal: 1, vertical: 1))
          }
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(kind == .alert ? 2 : 3),
        idealHeight: .finite(kind == .alert ? 6 : 4),
        maxHeight: .finite(kind == .alert ? 10 : 6),
        alignment: .topLeading
      )
      presentationActions
    }
  }

  private var sheetBody: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 0) {
        DeferredPayloadGroupView(
          kindName: "SheetContent",
          payloads: contentPayloads
        )
      }
      .padding(.init(horizontal: 1, vertical: 1))
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(4),
      idealHeight: .finite(12),
      maxHeight: .finite(20),
      alignment: .topLeading
    )
  }

  private var presentationActions: some View {
    HStack(spacing: 1) {
      ForEach(actionPayloads.indices, id: \.self) { index in
        DeferredPayloadView(payload: actionPayloads[index])
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

    let contentPayloads = deferredDeclaredBuilderChildren(from: toastContent)
    node.preferenceValues.merge(
      PresentationCoordinatorPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            requestID: .init(
              attachmentIdentity: node.identity,
              family: .toast,
              token: PresentationFamilyID.toast.rawValue
            ),
            attachmentIdentity: node.identity,
            family: .toast,
            priority: 0,
            surfacePayload: DeferredViewPayload {
              BuiltinToastHostedPresentation(
                contentPayloads: contentPayloads,
                style: style,
                duration: duration,
                dismiss: { [isPresented] in
                  isPresented.wrappedValue = false
                }
              )
            }
          )
        ]
      )
    )
    return [node]
  }
}

private struct BuiltinToastHostedPresentation: View {
  var contentPayloads: [DeferredViewPayload]
  var style: ToastStyle
  var duration: Double?
  var dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    EnvironmentReader(\.presentationPlacementContext) { placementContext in
      VStack(alignment: .leading, spacing: 0) {
        Spacer(minLength: 0)
        toastCard
      }
      .padding(.bottom, 1 + placementContext.familyIndex * 5)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .allowsHitTesting(false)
      .task {
        guard let duration, duration > 0 else {
          return
        }
        try? await Task.sleep(for: .seconds(duration))
        dismiss()
      }
    }
  }

  private var toastCard: some View {
    HStack(alignment: .center, spacing: 1) {
      Text(style.icon)
        .foregroundStyle(.terminalAccent(style.tone))
      VStack {
        DeferredPayloadGroupView(
          kindName: "ToastContent",
          payloads: contentPayloads
        )
      }
    }
    .padding(1)
    .background {
      Rectangle().chromeFill(.terminalSurfaceBackground)
    }
    .overlay {
      Rectangle().chromeStrokeBorder(
        .terminalBorder(style.tone)
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
  }
}

extension ResolvedNode {
  package mutating func setEnabledRecursively(
    _ isEnabled: Bool
  ) {
    var style = environmentSnapshot.style
    style.isEnabled = isEnabled
    environmentSnapshot.style = style

    for index in children.indices {
      children[index].setEnabledRecursively(isEnabled)
    }
  }
}
