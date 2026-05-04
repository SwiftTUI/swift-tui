public import SwiftTUICore

/// Matches focused key input for `View.onKeyPress`.
public struct KeyPressMatch: Equatable, Sendable {
  private enum Storage: Equatable, Sendable {
    case any
    case exact(KeyPress)
  }

  private let storage: Storage

  private init(storage: Storage) {
    self.storage = storage
  }

  /// Matches every key press delivered to the focused view.
  public static let any = Self(storage: .any)

  /// Matches an exact key plus modifier combination.
  public static func key(
    _ key: KeyEvent,
    modifiers: EventModifiers = []
  ) -> Self {
    Self(storage: .exact(KeyPress(key, modifiers: modifiers)))
  }

  /// Matches an exact key press.
  public static func keyPress(_ keyPress: KeyPress) -> Self {
    Self(storage: .exact(keyPress))
  }

  package func matches(_ keyPress: KeyPress) -> Bool {
    switch storage {
    case .any:
      true
    case .exact(let expected):
      expected == keyPress
    }
  }
}

extension View {
  /// Registers a key handler for this view while it is focused.
  ///
  /// Return `.handled` to consume the key press. Return `.ignored` to leave it
  /// available to other focused-key handlers and the runtime's default input
  /// routing.
  @MainActor
  public func onKeyPress(
    _ match: KeyPressMatch = .any,
    perform action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
  ) -> ModifiedContent<Self, KeyPressModifier> {
    modifier(
      KeyPressModifier(
        match: match,
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  /// Registers a key handler for an exact key plus modifier combination while
  /// this view is focused.
  @MainActor
  public func onKeyPress(
    _ key: KeyEvent,
    modifiers: EventModifiers = [],
    perform action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
  ) -> ModifiedContent<Self, KeyPressModifier> {
    onKeyPress(.key(key, modifiers: modifiers), perform: action)
  }
}

public struct KeyPressModifier: PrimitiveViewModifier, Sendable {
  package let match: KeyPressMatch
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable (KeyPress) -> KeyPressResult

  package init(
    match: KeyPressMatch,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable (KeyPress) -> KeyPressResult
  ) {
    self.match = match
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    context.localKeyHandlerRegistry?.register(
      identity: node.identity,
      keyPressHandler: { keyPress in
        guard match.matches(keyPress) else {
          return false
        }
        return withImperativeAuthoringContext(dynamicPropertyScope) {
          action(keyPress) == .handled
        }
      }
    )
    return [node]
  }
}
