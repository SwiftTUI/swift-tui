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
  ) -> DropDestinationModifier<Self> {
    DropDestinationModifier(content: self, action: action)
  }
}

public struct DropDestinationModifier<Content: View & Sendable>: View, ResolvableView {
  nonisolated let content: Content
  nonisolated let action: @MainActor @Sendable ([DroppedPath]) -> Bool

  init(
    content: Content,
    action: @escaping @MainActor @Sendable ([DroppedPath]) -> Bool
  ) {
    self.content = content
    self.action = action
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let node = content.resolve(in: context)
    context.dropDestinationRegistry?.register(at: node.identity, handler: action)
    return [node]
  }
}

// Forward the inner scope's identity so chained `.dropDestination`,
// `.keyCommand`, and `.paletteCommand` keep compiling: after the
// modifier, the wrapped view is still an ActionScope whose id equals
// the content's.
extension DropDestinationModifier: Identifiable where Content: ActionScope {
  public typealias ID = Content.ID
  nonisolated public var id: Content.ID { content.id }
}

extension DropDestinationModifier: ActionScope where Content: ActionScope {}
