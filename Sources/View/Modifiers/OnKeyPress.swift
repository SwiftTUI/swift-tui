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
  ///   .onKeyPress(.character("s"), modifiers: .control) {
  ///     save()
  ///     return .handled
  ///   }
  /// ```
  public func onKeyPress(
    _ key: LocalKeyEvent,
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
  /// The handler receives the full ``LocalKeyPress`` and returns a
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
    action: @escaping @MainActor @Sendable (LocalKeyPress) -> KeyPressResult
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
  var expectedKey: LocalKeyEvent?
  var expectedModifiers: EventModifiers
  let action: @MainActor @Sendable (LocalKeyPress) -> KeyPressResult

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)

    let dynamicPropertyScope = currentDynamicPropertyScope()
    let onKeyAction = action
    let matchKey = expectedKey
    let matchModifiers = expectedModifiers

    let binding = HotkeyBinding(
      key: LocalKeyPress(matchKey ?? .escape, modifiers: matchModifiers)
    )

    context.hotkeyRegistry?.register(binding: binding) { localKeyPress in
      if let matchKey {
        guard localKeyPress.key == matchKey && localKeyPress.modifiers == matchModifiers else {
          return false
        }
      }

      let result: KeyPressResult
      if let dynamicPropertyScope {
        result = withDynamicPropertyScope(dynamicPropertyScope) {
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
