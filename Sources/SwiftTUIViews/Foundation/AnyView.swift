package import SwiftTUICore

/// A type-erased terminal view.
///
/// Use `AnyView` when a call site must store heterogeneous view values while
/// still participating in the normal authored `View` surface. Prefer typed
/// `@ViewBuilder` composition and generic `Content: View` storage when those
/// are practical. See the ``AnyView`` article for usage examples and identity
/// behavior.
public struct AnyView: PrimitiveView, ResolvableView {
  private let storage: AnyViewStorage

  package init<V: View & ResolvableView>(resolving view: V) {
    storage = Self.makeStorage(view, authoringContext: nil)
  }

  package init<V: View>(
    scoped view: V,
    authoringContext: AuthoringContext?
  ) {
    storage = Self.makeStorage(view, authoringContext: authoringContext)
  }

  /// Erases the concrete type of `view`.
  ///
  /// Prefer `scopedAnyView(...)` when authored content will be stored for later
  /// evaluation, because that helper also restores the original
  /// dynamic-property scope.
  public init<V: View>(_ view: V) {
    storage = Self.makeStorage(view, authoringContext: nil)
  }

  package init<Node: ViewNode>(erasing view: Node) {
    storage = .init(
      typeID: .init(erasing: Node.self),
      authoringContext: nil,
      resolve: { context in
        view.resolve(in: context)
      }
    )
  }

  public var body: Never {
    fatalError("AnyView is a type-erased view.")
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let payloadContext = context.child(component: storage.typeID.identityComponent)
    // The payload's stored view resolves through this Content node — a
    // non-transparent hosting boundary. Host-escaping entity routes must not
    // be claimed here (see `ResolveContext.entityHosting`).
    let contentContext = payloadContext.child(component: .named("Content")).asEntityHost()
    let content = storage.resolve(contentContext)

    if content.kind == .view("Group"), content.identity == contentContext.identity {
      // A multi-element erased payload normalized to a synthesized group at
      // the content identity. Hoist the elements: the enclosing `resolveView`
      // re-normalizes them into a group at this AnyView's own identity, which
      // the container child walk splices into its declared children — so the
      // erased content lays out exactly like the same elements authored
      // inline (a two-element payload inside a VStack occupies two stack
      // slots, not one overlaid box). The hoisted elements keep their
      // type-keyed content identities, so a payload type swap still replaces
      // the whole subtree. The group's minted content node is spliced out of
      // every children array; resolve-lifetime scope automatically owns that
      // detached mint at the nearest declaring host.
      context.viewGraph?.reportDetachedResolvedLifetimeResult(content)
      return content.children
    }

    let payloadShell = ResolvedNode(
      identity: payloadContext.identity,
      kind: .view("AnyViewPayload"),
      typeDiscriminator: storage.typeID.typeDiscriminator,
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )
    context.viewGraph?.prepareStructuralChildren(
      for: context.identity,
      children: [payloadShell]
    )
    let payload = ResolvedNode(
      identity: payloadContext.identity,
      kind: .view("AnyViewPayload"),
      typeDiscriminator: storage.typeID.typeDiscriminator,
      children: [content],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("AnyView"),
        typeDiscriminator: ObjectIdentifier(AnyView.self),
        children: [payload],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }

  private static func makeStorage<V: View>(
    _ view: V,
    authoringContext: AuthoringContext?
  ) -> AnyViewStorage {
    AnyViewStorage(
      typeID: .init(V.self),
      authoringContext: authoringContext,
      resolve: { context in
        resolveView(
          view,
          in: context,
          authoringContextOverride: authoringContext
        )
      }
    )
  }
}

extension AnyView: ViewNode {
  package func resolve(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}

private struct AnyViewStorage {
  let typeID: ErasedViewTypeID
  let authoringContext: AuthoringContext?
  let resolve: @MainActor (ResolveContext) -> ResolvedNode
}
