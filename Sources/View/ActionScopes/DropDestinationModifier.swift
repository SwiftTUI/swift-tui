public import Core

extension ActionScope where Self: View & Sendable {
  /// Declares this scope as a file-drop destination.
  ///
  /// The closure fires when a file is dropped on the terminal (or a
  /// file-path-shaped payload is pasted) while this scope is on the
  /// current focus chain. Dispatch is leafmost-first: inner scopes see
  /// the drop before outer ones. Returning `true` consumes the drop;
  /// returning `false` bubbles it to the next outer scope, ultimately
  /// falling through to ordinary text paste if no scope claims it.
  ///
  /// `.dropDestination` is intentionally available only on
  /// `ActionScope` conformers — attaching it to an arbitrary `View`
  /// would introduce a spatial-dispatch ambiguity a terminal cannot
  /// resolve.
  @MainActor
  public func dropDestination(
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) -> some View & ActionScope & Sendable {
    modifier(
      DropDestinationRegistrationModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

public struct DropDestinationRegistrationModifier: PrimitiveViewModifier, Sendable {
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable ([DroppedPath]) -> Bool

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) {
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    context.dropDestinationRegistry?.register(
      at: node.identity,
      handler: { paths in
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action(paths)
        }
      }
    )
    return [node]
  }
}
