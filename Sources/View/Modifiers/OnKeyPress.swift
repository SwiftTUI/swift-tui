public import Core

// MARK: - View Modifier

extension View {
  /// Handles key press events on this view, regardless of focus.
  ///
  /// The handler fires when the specified key and modifiers match an incoming
  /// key event. Return `.handled` to consume the event or `.ignored` to let
  /// it propagate.
  ///
  /// ```swift
  /// VStack { ... }
  ///   .onKeyPress(.character("s"), modifiers: .ctrl) {
  ///     save()
  ///     return .handled
  ///   }
  /// ```
  public func onKeyPress(
    _ key: KeyEvent,
    modifiers: EventModifiers = [],
    action: @escaping @MainActor @Sendable () -> KeyPressResult
  ) -> some View {
    OnKeyPressModifier(
      content: self,
      expectedKey: key,
      expectedModifiers: modifiers,
      action: { _ in action() }
    )
  }

  /// Handles any key press event on this view, regardless of focus.
  ///
  /// The handler receives the full ``KeyPress`` and returns a
  /// ``KeyPressResult`` to indicate whether the event was consumed.
  ///
  /// ```swift
  /// VStack { ... }
  ///   .onKeyPress { keyPress in
  ///     if keyPress.key == .character("?") {
  ///       showHelp()
  ///       return .handled
  ///     }
  ///     return .ignored
  ///   }
  /// ```
  public func onKeyPress(
    action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
  ) -> some View {
    OnKeyPressModifier(
      content: self,
      expectedKey: nil,
      expectedModifiers: [],
      action: action
    )
  }
}

// MARK: - Implementation

private struct OnKeyPressModifier<Content: View>: View, ResolvableView {
  var content: Content
  var expectedKey: KeyEvent?
  var expectedModifiers: EventModifiers
  let action: @MainActor @Sendable (KeyPress) -> KeyPressResult
  private let authoringScope: AuthoringContext?

  init(
    content: Content,
    expectedKey: KeyEvent?,
    expectedModifiers: EventModifiers,
    action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
  ) {
    self.content = content
    self.expectedKey = expectedKey
    self.expectedModifiers = expectedModifiers
    self.action = action
    authoringScope = currentAuthoringContext()
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)

    let onKeyAction = action
    let matchKey = expectedKey
    let matchModifiers = expectedModifiers

    let binding = HotkeyBinding(
      key: KeyPress(matchKey ?? .escape, modifiers: matchModifiers)
    )

    context.hotkeyRegistry?.register(identity: context.identity, binding: binding) {
      localKeyPress in
      if let matchKey {
        guard localKeyPress.key == matchKey && localKeyPress.modifiers == matchModifiers else {
          return false
        }
      }

      let result: KeyPressResult
      if let authoringScope {
        result = withAuthoringContext(authoringScope) {
          onKeyAction(localKeyPress)
        }
      } else {
        result = onKeyAction(localKeyPress)
      }
      return result == .handled
    }

    return [node]
  }
}
