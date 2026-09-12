public import SwiftTUICore

/// A direction requested by an unmodified arrow key.
public enum MoveCommandDirection: CaseIterable, Hashable, Sendable {
  /// Move toward the preceding visual row.
  case up
  /// Move toward the following visual row.
  case down
  /// Move toward the preceding visual column.
  case left
  /// Move toward the following visual column.
  case right
}

extension View {
  /// Handles an unmodified arrow key on the focused view's hosting chain.
  ///
  /// The nearest view receives the command first. Return `.handled` to consume
  /// it or `.ignored` to let enclosing handlers and default navigation try it.
  /// Handlers at the same view identity follow `onKeyPress` stacking order
  /// (outermost modifier first). Disabled views do not install a handler.
  @MainActor
  public func onMoveCommand(
    perform action: @escaping @MainActor @Sendable (MoveCommandDirection) -> KeyPressResult
  ) -> ModifiedContent<Self, KeyPressModifier> {
    onKeyPress { key in
      guard key.modifiers.isEmpty else { return .ignored }
      let direction: MoveCommandDirection
      switch key.key {
      case .arrowUp: direction = .up
      case .arrowDown: direction = .down
      case .arrowLeft: direction = .left
      case .arrowRight: direction = .right
      default: return .ignored
      }
      return action(direction)
    }
  }

  /// Handles unmodified Escape on the focused view's hosting chain.
  ///
  /// Return `.ignored` to bubble to an enclosing handler or the runtime's
  /// presentation-dismissal route. Return `.handled` when the command has been
  /// consumed. Sibling focus scopes do not receive the command, and disabled
  /// views do not install a handler. This modifier does not handle configured
  /// scene exit chords such as Control-C.
  @MainActor
  public func onExitCommand(
    perform action: @escaping @MainActor @Sendable () -> KeyPressResult
  ) -> ModifiedContent<Self, KeyPressModifier> {
    onKeyPress(.escape) { _ in action() }
  }
}
