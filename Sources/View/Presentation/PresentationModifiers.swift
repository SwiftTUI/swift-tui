package import Core

package enum TerminalPresentationKind: Equatable, Sendable {
  case alert
  case confirmationDialog
  case sheet

  var debugName: String {
    switch self {
    case .alert:
      "alert"
    case .confirmationDialog:
      "confirmationDialog"
    case .sheet:
      "sheet"
    }
  }

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
}

// AnyView policy: retain heterogeneous action and message content here while
// modal requests are hoisted through preferences to the root presentation host.
package struct TerminalPresentationRequest: @unchecked Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var attachmentIdentity: Identity
  var title: String
  var kind: TerminalPresentationKind
  var backdropOpacity: Double
  var actionViews: [AnyView]
  var messageViews: [AnyView]
  /// Arbitrary content for sheet presentations (used instead of actionViews/messageViews).
  var contentViews: [AnyView]
  var dismiss: @MainActor @Sendable () -> Void

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    "TerminalPresentationRequest(identity: \(attachmentIdentity.path), kind: \(kind.debugName), title: \(String(reflecting: title)), actions: \(actionViews.count), messages: \(messageViews.count), content: \(contentViews.count))"
  }
}

package struct TerminalPresentationPreferenceValue: @unchecked Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var requests: [TerminalPresentationRequest] = []

  package var description: String {
    debugDescription
  }

  package var debugDescription: String {
    requests.map(\.debugDescription).joined(separator: ", ")
  }
}

package enum TerminalPresentationPreferenceKey: PreferenceKey {
  package static let defaultValue = TerminalPresentationPreferenceValue()

  package static func reduce(
    value: inout TerminalPresentationPreferenceValue,
    nextValue: () -> TerminalPresentationPreferenceValue
  ) {
    value.requests.append(contentsOf: nextValue().requests)
  }
}

package struct TerminalPresentationHostingRoot<Content: View>: View, ResolvableView {
  package var content: Content

  package init(content: Content) {
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: context),
      in: context
    )
    let requests = baseNode.preferenceValues[TerminalPresentationPreferenceKey.self].requests
    guard !requests.isEmpty else {
      return [baseNode]
    }

    let hostContext = context.child(component: .named("PresentationHost"))
    let baseContext = hostContext.child(component: .named("base"))
    baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: baseContext),
      in: baseContext
    )
    baseNode.setEnabledRecursively(false)
    let overlayNode = TerminalPresentationOverlayHost(requests: requests).resolve(
      in: hostContext.child(component: .named("overlay"))
    )

    return [
      ResolvedNode(
        identity: hostContext.identity,
        kind: .view("PresentationHost"),
        children: [baseNode, overlayNode],
        environmentSnapshot: hostContext.environment,
        transactionSnapshot: hostContext.transaction,
        layoutBehavior: .overlay(alignment: .topLeading)
      )
    ]
  }
}

extension View {
  public func alert<S: StringProtocol>(
    _ title: S,
    isPresented: Binding<Bool>
  ) -> some View {
    TerminalPresentationModifier(
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
    TerminalPresentationModifier(
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
    TerminalPresentationModifier(
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
    TerminalPresentationModifier(
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
    TerminalSheetModifier(
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
    TerminalSheetModifier(
      content: self,
      title: String(title),
      isPresented: isPresented,
      sheetContent: sheetContent()
    )
  }
}

@MainActor
private func defaultPresentationActions(
  kind: TerminalPresentationKind,
  isPresented: Binding<Bool>
) -> Button<Text> {
  Button(
    kind.defaultDismissTitle,
    action: {
      isPresented.wrappedValue = false
    }
  )
}

// AnyView policy: retain heterogeneous child storage here for authored message
// and action content in hoisted terminal presentations.
private struct TerminalPresentationModifier<
  Content: View, Actions: View,
  Message: View
>: View, ResolvableView {
  var content: Content
  var title: String
  var isPresented: Binding<Bool>
  var kind: TerminalPresentationKind
  var actions: Actions
  var message: Message

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    node.preferenceValues.merge(
      TerminalPresentationPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            attachmentIdentity: node.identity,
            title: title,
            kind: kind,
            backdropOpacity: 0,
            actionViews: declaredBuilderChildren(from: actions),
            messageViews: declaredBuilderChildren(from: message),
            contentViews: [],
            dismiss: { [isPresented] in
              isPresented.wrappedValue = false
            }
          )
        ]
      )
    )
    return [node]
  }
}

// AnyView policy: retain heterogeneous sheet content while hoisting through
// preferences to the root presentation host.
private struct TerminalSheetModifier<Content: View, SheetContent: View>: View,
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
      TerminalPresentationPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            attachmentIdentity: node.identity,
            title: title,
            kind: .sheet,
            backdropOpacity: 0,
            actionViews: [],
            messageViews: [],
            contentViews: declaredBuilderChildren(from: sheetContent),
            dismiss: { [isPresented] in
              isPresented.wrappedValue = false
            }
          )
        ]
      )
    )
    return [node]
  }
}

private struct TerminalPresentationOverlayHost: View {
  var requests: [TerminalPresentationRequest]

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(requests.indices, id: \.self) { index in
        TerminalHostedPresentation(request: requests[index])
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TerminalHostedPresentation: View {
  var request: TerminalPresentationRequest

  var body: some View {
    ZStack(alignment: .topLeading) {
      if request.backdropOpacity > 0 {
        Rectangle()
          .fill(.background.opacity(request.backdropOpacity))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      TerminalPresentationSurface(
        title: request.title,
        kind: request.kind,
        actionViews: request.actionViews,
        messageViews: request.messageViews,
        contentViews: request.contentViews,
        dismiss: request.dismiss
      )
      .padding(
        .init(
          top: 1,
          leading: 1,
          bottom: 1,
          trailing: 1
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: request.kind.alignment)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TerminalPresentationSurface: View, ResolvableView {
  var title: String
  var kind: TerminalPresentationKind
  var actionViews: [AnyView]
  var messageViews: [AnyView]
  var contentViews: [AnyView]
  var dismiss: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // Register escape-to-dismiss key handler on the presentation surface.
    context.localKeyHandlerRegistry?.register(identity: context.identity) {
      [dismiss] event in
      guard event == .escape else {
        return false
      }
      dismiss()
      return true
    }
    return resolveViewElements(body, in: context)
  }

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
          if !messageViews.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              combinedView(from: messageViews, kindName: "PresentationMessage")
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
        combinedView(from: contentViews, kindName: "SheetContent")
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
      ForEach(actionViews.indices, id: \.self) { index in
        actionViews[index]
          .fixedSize()
      }
    }
    .fixedSize()
    .padding(.init(horizontal: 1, vertical: 0))

  }
}

extension ResolvedNode {
  fileprivate mutating func setEnabledRecursively(
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

private struct ToastRequest: @unchecked Sendable {
  var contentViews: [AnyView]
  var style: ToastStyle
  var duration: Double?
  var dismiss: @MainActor @Sendable () -> Void
}

private struct ToastPreferenceValue: Sendable {
  var requests: [ToastRequest] = []
}

private enum ToastPreferenceKey: PreferenceKey {
  static let defaultValue = ToastPreferenceValue()

  static func reduce(
    value: inout ToastPreferenceValue,
    nextValue: () -> ToastPreferenceValue
  ) {
    value.requests.append(contentsOf: nextValue().requests)
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

    let contentViews = declaredBuilderChildren(from: toastContent)
    node.preferenceValues.merge(
      ToastPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            contentViews: contentViews,
            style: style,
            duration: duration,
            dismiss: { [isPresented] in
              isPresented.wrappedValue = false
            }
          )
        ]
      )
    )
    return [node]
  }
}

package struct ToastHostingRoot<Content: View>: View, ResolvableView {
  package var content: Content

  package init(content: Content) {
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: context),
      in: context
    )
    let requests = baseNode.preferenceValues[ToastPreferenceKey.self].requests
    guard !requests.isEmpty else {
      return [baseNode]
    }

    let hostContext = context.child(component: .named("ToastHost"))
    let baseContext = hostContext.child(component: .named("base"))
    let hostedBaseNode = normalizeResolvedElements(
      resolveViewElements(content, in: baseContext),
      in: baseContext
    )
    let overlayNode = ToastOverlayHost(requests: requests).resolve(
      in: hostContext.child(component: .named("overlay"))
    )

    return [
      ResolvedNode(
        identity: hostContext.identity,
        kind: .view("ToastHost"),
        children: [hostedBaseNode, overlayNode],
        environmentSnapshot: hostContext.environment,
        transactionSnapshot: hostContext.transaction,
        layoutBehavior: .overlay(alignment: .topLeading)
      )
    ]
  }
}

private struct ToastOverlayHost: View {
  var requests: [ToastRequest]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      ForEach(requests.indices, id: \.self) { index in
        ToastSurface(request: requests[index])
      }
    }
    .padding(.bottom, 1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .allowsHitTesting(false)
  }
}

private struct ToastSurface: View {
  var request: ToastRequest

  var body: some View {
    toastContent
      .task {
        guard let duration = request.duration, duration > 0 else {
          return
        }
        try? await Task.sleep(for: .seconds(duration))
        request.dismiss()
      }
  }

  @ViewBuilder
  private var toastContent: some View {
    HStack(alignment: .center, spacing: 1) {
      Text(request.style.icon)
        .foregroundStyle(.terminalAccent(request.style.tone))
      VStack {
        combinedView(from: request.contentViews, kindName: "ToastContent")
      }
    }
    .padding(1)
    .background {
      Rectangle().chromeFill(.terminalSurfaceBackground)
    }
    .overlay {
      Rectangle().chromeStrokeBorder(
        .terminalBorder(request.style.tone)
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
