public import SwiftTUICore

extension ActionScope where Self: View & Sendable {
  /// Declares a keyboard-shortcut command at this scope's root.
  ///
  /// Fires only when this scope is on the current focus chain and no
  /// shallower scope on that chain has claimed the same
  /// `(key, modifiers)` combination (strict shallowest-wins).
  ///
  /// `modifiers` must be non-empty. Single-key bindings are reserved
  /// for framework-internal dispatch (typing, arrow navigation, Tab,
  /// Enter, Escape); modifier-less registrations are silently dropped
  /// and the command will never fire.
  @MainActor
  public func keyCommand(
    _ description: String,
    key: KeyEvent,
    modifiers: EventModifiers,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    modifier(
      KeyCommandRegistrationModifier(
        binding: KeyBinding(key: key, modifiers: modifiers),
        description: description,
        isEnabled: isEnabled,
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

public struct KeyCommandRegistrationModifier: PrimitiveViewModifier, Sendable {
  package let binding: KeyBinding
  package let description: String
  package let isEnabled: Bool
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable () -> Void

  package init(
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.binding = binding
    self.description = description
    self.isEnabled = isEnabled
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    guard !binding.modifiers.isEmpty else {
      // Modifier-less registrations are framework-reserved for typing,
      // arrow navigation, Tab, Enter, and Escape. Silently drop the
      // registration; the command will never fire.
      return [node]
    }
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    context.commandRegistry?.registerKeyCommand(
      at: node.identity,
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: {
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action()
        }
      }
    )
    return [node]
  }
}
