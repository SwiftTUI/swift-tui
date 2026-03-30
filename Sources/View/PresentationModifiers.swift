package import Core

private enum TerminalPresentationKind: Equatable, Sendable {
  case alert
  case confirmationDialog

  var debugName: String {
    switch self {
    case .alert:
      "alert"
    case .confirmationDialog:
      "confirmationDialog"
    }
  }

  var alignment: Alignment {
    switch self {
    case .alert:
      .center
    case .confirmationDialog:
      .bottomLeading
    }
  }

  var presentationRole: PresentationRole {
    switch self {
    case .alert:
      .alert
    case .confirmationDialog:
      .confirmationDialog
    }
  }

  var defaultDismissTitle: String {
    switch self {
    case .alert:
      "Dismiss"
    case .confirmationDialog:
      "Cancel"
    }
  }
}

// AnyView policy: retain heterogeneous action and message content here while
// modal requests are hoisted through preferences to the root presentation host.
private struct TerminalPresentationRequest: @unchecked Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var attachmentIdentity: Identity
  var title: String
  var kind: TerminalPresentationKind
  var actionViews: [AnyView]
  var messageViews: [AnyView]
  var dismiss: @MainActor @Sendable () -> Void

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    "TerminalPresentationRequest(identity: \(attachmentIdentity.path), kind: \(kind.debugName), title: \(String(reflecting: title)), actions: \(actionViews.count), messages: \(messageViews.count))"
  }
}

private struct TerminalPresentationPreferenceValue: @unchecked Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var requests: [TerminalPresentationRequest] = []

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    requests.map(\.debugDescription).joined(separator: ", ")
  }
}

private enum TerminalPresentationPreferenceKey: PreferenceKey {
  static let defaultValue = TerminalPresentationPreferenceValue()

  static func reduce(
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

    baseNode.setEnabledRecursively(false)

    let hostContext = context.child(component: .named("PresentationHost"))
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
      actionViews: defaultPresentationActions(
        kind: .alert,
        isPresented: isPresented
      ),
      messageViews: []
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
      actionViews: declaredBuilderChildren(from: actions()),
      messageViews: declaredBuilderChildren(from: message())
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
      actionViews: defaultPresentationActions(
        kind: .confirmationDialog,
        isPresented: isPresented
      ),
      messageViews: []
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
      actionViews: declaredBuilderChildren(from: actions()),
      messageViews: declaredBuilderChildren(from: message())
    )
  }
}

@MainActor
private func defaultPresentationActions(
  kind: TerminalPresentationKind,
  isPresented: Binding<Bool>
) -> [AnyView] {
  [
    scopedAnyView {
      Button(
        kind.defaultDismissTitle,
        action: {
          isPresented.wrappedValue = false
        }
      )
    }
  ]
}

// AnyView policy: retain heterogeneous child storage here for authored message
// and action content in hoisted terminal presentations.
private struct TerminalPresentationModifier<Content: View>: View, ResolvableView {
  var content: Content
  var title: String
  var isPresented: Binding<Bool>
  var kind: TerminalPresentationKind
  var actionViews: [AnyView]
  var messageViews: [AnyView]

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
            actionViews: actionViews,
            messageViews: messageViews,
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
    ZStack(
      alignment: .topLeading,
      children: requests.map { request in
        AnyView(
          TerminalHostedPresentation(request: request)
        )
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TerminalHostedPresentation: View {
  var request: TerminalPresentationRequest

  var body: some View {
    TerminalPresentationSurface(
      title: request.title,
      kind: request.kind,
      actionViews: request.actionViews,
      messageViews: request.messageViews,
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
}

private struct TerminalPresentationSurface: View {
  var title: String
  var kind: TerminalPresentationKind
  var actionViews: [AnyView]
  var messageViews: [AnyView]
  var dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 1) {
        Text(title)
          .bold()
        Spacer(minLength: 0)
        Button("×", role: .close, action: dismiss)
          .buttonStyle(.borderedProminent)
      }
      .frame(height: 1, alignment: .leading)
      .padding(.init(horizontal: 1, vertical: 0))
      .background(.terminalRow(kind == .alert ? .neutral : .accent, isSelected: true))

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
