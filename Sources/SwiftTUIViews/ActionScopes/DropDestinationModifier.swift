public import SwiftTUICore

extension ActionScope where Self: View & Sendable {
  /// Declares this scope as a file-drop destination.
  ///
  /// The closure fires if this scope is on the current focus chain.
  /// A file drop on the terminal can fire it. A pasted, file-path-shaped payload can also fire it.
  /// Dispatch starts at the leaf: inner scopes see
  /// the drop before outer ones. Returning `true` consumes the drop.
  /// Returning `false` bubbles it to the next outer scope, ultimately
  /// falling through to ordinary text paste if no scope claims it.
  ///
  /// `.dropDestination` is intentionally available only on
  /// `ActionScope` conformers.
  /// An arbitrary `View` has no terminal location that can resolve the spatial-dispatch ambiguity.
  @MainActor
  public func dropDestination(
    action: @escaping @MainActor @Sendable ([DroppedPath], DropContext) -> Bool
  ) -> some View & ActionScope & Sendable {
    modifier(
      DropDestinationRegistrationModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  /// Declares this scope as a file-drop destination without spatial context.
  @MainActor
  public func dropDestination(
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) -> some View & ActionScope & Sendable {
    dropDestination { paths, _ in
      action(paths)
    }
  }
}

public struct DropDestinationRegistrationModifier: PrimitiveViewModifier, Sendable {
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable ([DroppedPath], DropContext) -> Bool

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable ([DroppedPath], DropContext) -> Bool
  ) {
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    // Construction-scope preference: the drop action captures the enclosing
    // body's `@State` (a consume-policy flag read at dispatch), so it must
    // dispatch under the scope that authored it, not whichever node this
    // modifier happens to resolve below.
    let intake = HandlerDescriptorIntake(
      context: context,
      preferringSnapshot: authoringContext
    )
    intake.registerDropDestination(at: node.identity, handler: action)
    return [node]
  }
}
