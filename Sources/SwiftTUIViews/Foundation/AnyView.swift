package import SwiftTUICore

/// A type-erased terminal view.
///
/// Use `AnyView` when a call site must store heterogeneous view values while
/// still participating in the normal authored `View` surface. Prefer typed
/// `@ViewBuilder` composition and generic `Content: View` storage when those
/// are practical.
public struct AnyView: View, ResolvableView {
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
    let payload = ResolvedNode(
      identity: payloadContext.identity,
      kind: .view("AnyViewPayload"),
      typeDiscriminator: storage.typeID.typeDiscriminator,
      children: AnyViewPayload(storage: storage).resolveElements(in: payloadContext),
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

private struct AnyViewPayload: View, ResolvableView {
  let storage: AnyViewStorage

  var body: Never {
    fatalError("AnyViewPayload is resolved directly.")
  }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var contentContext = context.child(component: .named("Content"))
    contentContext.explicitIdentityNamespace = contentContext.identity
    return [
      storage.resolve(contentContext)
    ]
  }
}
