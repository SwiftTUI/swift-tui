import Core

private enum TerminalPresentationKind: Equatable, Sendable {
  case alert
  case confirmationDialog

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
    AnyView(
      Button(
        kind.defaultDismissTitle,
        action: {
          isPresented.wrappedValue = false
        }
      )
    )
  ]
}

// AnyView policy: retain heterogeneous child storage here for authored message
// and action content in terminal presentations.
private struct TerminalPresentationModifier<Content: View>: View {
  var content: Content
  var title: String
  var isPresented: Binding<Bool>
  var kind: TerminalPresentationKind
  var actionViews: [AnyView]
  var messageViews: [AnyView]

  var body: some View {
    Group {
      if isPresented.wrappedValue {
        ZStack(alignment: kind.alignment) {
          content
            .disabled(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

          TerminalPresentationSurface(
            title: title,
            kind: kind,
            actionViews: actionViews,
            messageViews: messageViews,
            dismiss: { [isPresented] in isPresented.wrappedValue = false }
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
      } else {
        content
      }
    }
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
