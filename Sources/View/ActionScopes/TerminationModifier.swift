public import Core

extension View {
  /// Registers a handler that runs before the interactive session terminates.
  ///
  /// Return `.cancel` to keep the session alive for cancellable requests such
  /// as configured exit keys and host termination signals. Input-stream EOF
  /// still ends the session after handlers run.
  @MainActor
  public func onTerminationRequest(
    perform action: @escaping @MainActor @Sendable (TerminationRequest) -> TerminationDisposition
  ) -> ModifiedContent<Self, TerminationRequestModifier> {
    modifier(
      TerminationRequestModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

public struct TerminationRequestModifier: PrimitiveViewModifier, Sendable {
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable (TerminationRequest) -> TerminationDisposition

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable (TerminationRequest) -> TerminationDisposition
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
    context.localTerminationRegistry?.register(
      identity: node.identity,
      handler: { request in
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action(request)
        }
      }
    )
    return [node]
  }
}
