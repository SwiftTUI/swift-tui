public import SwiftTUICore

/// A proxy for imperative scroll commands inside a ``ScrollViewReader`` scope.
public struct ScrollViewProxy {
  private let bridge: ScrollViewProxyBridge

  @MainActor
  fileprivate init(bridge: ScrollViewProxyBridge) {
    self.bridge = bridge
  }

  /// Scrolls the first target matching `identity` into view.
  @discardableResult
  @MainActor
  public func scrollTo(
    _ identity: Identity,
    anchor: UnitPoint? = nil
  ) -> Bool {
    bridge.scrollTo(
      .init(
        identity: identity,
        explicitIDComponent: explicitIDComponent(for: identity)
      ),
      anchor: anchor
    )
  }

  /// Scrolls the first target matching an authored collection or explicit ID into view.
  @discardableResult
  @MainActor
  public func scrollTo<ID: Hashable & Sendable>(
    _ id: ID,
    anchor: UnitPoint? = nil
  ) -> Bool {
    bridge.scrollTo(
      .init(explicitIDComponent: explicitIDComponent(for: id)),
      anchor: anchor
    )
  }

  /// Scrolls the first scroll view in this reader scope to an edge.
  @discardableResult
  @MainActor
  public func scrollTo(
    edge: Edge
  ) -> Bool {
    bridge.scrollTo(edge: edge)
  }

  /// Scrolls the first scroll view in this reader scope by cell deltas.
  @discardableResult
  @MainActor
  public func scrollBy(
    x deltaX: Int = 0,
    y deltaY: Int = 0
  ) -> Bool {
    bridge.scrollBy(x: deltaX, y: deltaY)
  }

  /// Scrolls the first scroll view in this reader scope to absolute cell offsets.
  @discardableResult
  @MainActor
  public func scrollTo(
    x: Int? = nil,
    y: Int? = nil
  ) -> Bool {
    bridge.scrollTo(x: x, y: y)
  }
}

/// Provides imperative scroll control for descendant scroll views.
public struct ScrollViewReader<Content: View>: PrimitiveView, ResolvableView {
  private let bridge: ScrollViewProxyBridge
  private let content: Content

  @MainActor
  public init(
    @ViewBuilder content: (ScrollViewProxy) -> Content
  ) {
    bridge = ScrollViewProxyBridge()
    self.content = content(ScrollViewProxy(bridge: bridge))
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentContext = context.child(component: .named("ScrollViewReaderContent"))
    bridge.configure(
      registry: context.scrollCommandRegistry,
      scopeIdentity: context.identity,
      invalidationIdentity: contentContext.identity,
      invalidator: context.invalidationProxy?.invalidator
    )
    return content.resolveElements(in: contentContext)
  }
}

@MainActor
private final class ScrollViewProxyBridge {
  private weak var invalidator: (any Invalidating)?
  private var registry: LocalScrollPositionRegistry?
  private var scopeIdentity: Identity?
  private var invalidationIdentity: Identity?

  func configure(
    registry: LocalScrollPositionRegistry?,
    scopeIdentity: Identity,
    invalidationIdentity: Identity,
    invalidator: (any Invalidating)?
  ) {
    self.registry = registry
    self.scopeIdentity = scopeIdentity
    self.invalidationIdentity = invalidationIdentity
    self.invalidator = invalidator
  }

  @discardableResult
  func scrollTo(
    _ query: ScrollTargetQuery,
    anchor: UnitPoint?
  ) -> Bool {
    let changed =
      registry?.scrollToTarget(
        query,
        anchor: anchor,
        scopeIdentity: scopeIdentity
      ) ?? false
    requestInvalidationIfNeeded(changed)
    return changed
  }

  @discardableResult
  func scrollTo(edge: Edge) -> Bool {
    let changed =
      registry?.scrollToEdge(
        edge,
        scopeIdentity: scopeIdentity
      ) ?? false
    requestInvalidationIfNeeded(changed)
    return changed
  }

  @discardableResult
  func scrollBy(
    x deltaX: Int,
    y deltaY: Int
  ) -> Bool {
    let changed =
      registry?.scrollBy(
        x: deltaX,
        y: deltaY,
        scopeIdentity: scopeIdentity
      ) ?? false
    requestInvalidationIfNeeded(changed)
    return changed
  }

  @discardableResult
  func scrollTo(
    x: Int?,
    y: Int?
  ) -> Bool {
    let changed =
      registry?.scrollTo(
        x: x,
        y: y,
        scopeIdentity: scopeIdentity
      ) ?? false
    requestInvalidationIfNeeded(changed)
    return changed
  }

  private func requestInvalidationIfNeeded(_ changed: Bool) {
    guard changed, let invalidationIdentity else {
      return
    }
    invalidator?.requestInvalidation(of: [invalidationIdentity])
  }
}

private func explicitIDComponent<ID: Hashable>(
  for id: ID
) -> String? {
  Identity(components: [] as [IdentityComponent]).explicitID(id).lastComponent
}
