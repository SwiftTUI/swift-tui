public import Core

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
  ) -> KeyCommandModifier<Self> {
    KeyCommandModifier(
      content: self,
      binding: KeyBinding(key: key, modifiers: modifiers),
      description: description,
      isEnabled: isEnabled,
      action: action
    )
  }
}

public struct KeyCommandModifier<Content: View & Sendable>: View, ResolvableView {
  nonisolated let content: Content
  let binding: KeyBinding
  let description: String
  let isEnabled: Bool
  let action: @MainActor @Sendable () -> Void

  init(
    content: Content,
    binding: KeyBinding,
    description: String,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.content = content
    self.binding = binding
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    guard !binding.modifiers.isEmpty else {
      // Modifier-less registrations are framework-reserved for typing,
      // arrow navigation, Tab, Enter, and Escape. Silently drop the
      // registration; the command will never fire.
      return [node]
    }
    context.commandRegistry?.registerKeyCommand(
      at: node.identity,
      binding: binding,
      description: description,
      isEnabled: isEnabled,
      action: action
    )
    return [node]
  }
}

// Forward the inner scope's identity so chained `.keyCommand` and
// `.paletteCommand` calls keep compiling: after the modifier, the
// wrapped view is still an ActionScope whose id equals the content's.
extension KeyCommandModifier: Identifiable where Content: ActionScope {
  public typealias ID = Content.ID
  nonisolated public var id: Content.ID { content.id }
}

extension KeyCommandModifier: ActionScope where Content: ActionScope {}
