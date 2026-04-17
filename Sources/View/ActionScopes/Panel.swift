public import Core

/// Controls how focus enters a Panel's descendants.
public enum FocusContainment: Sendable {
  /// Default: Tab reaches focusable descendants of the Panel.
  case open
  /// Panel is the focus stop; Tab skips the Panel's focusable
  /// descendants. Drill-in mechanism deferred to a future design.
  case sealed
}

/// A rectangular consumer-controlled area that conforms to
/// `ActionScope`.
///
/// Panel has no default UI chrome. Visual treatment is the consumer's
/// responsibility via standard modifiers (`.border`, `.background`,
/// `.padding`, etc.).
///
/// A Panel is focusable and participates in the focus topology. When a
/// Panel enters the focus chain, the Panel itself is focused first —
/// descendants are reached via Tab or explicit focus requests.
///
/// Pair with `.keyCommand(...)`, `.paletteCommand(...)`, or
/// `.focusContainment(_:)` to configure.
public struct Panel<ID: Hashable & Sendable, Content: View>: View, ActionScope, ResolvableView {
  public let id: ID
  package let containment: FocusContainment
  package let content: Content

  public init(
    id: ID,
    @ViewBuilder content: () -> Content
  ) {
    self.id = id
    self.containment = .open
    self.content = content()
  }

  package init(
    id: ID,
    containment: FocusContainment,
    content: Content
  ) {
    self.id = id
    self.containment = containment
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let childNode = content.resolve(in: context.child(component: .named("content")))
    var metadata = focusStructureMetadata(scopeBoundary: true)
    metadata.isFocusable = true
    if containment == .sealed {
      metadata.sealsFocusDescendants = true
    }
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Panel"),
        children: [childNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: metadata
      )
    ]
  }
}

extension Panel {
  /// Configures focus containment for this Panel.
  public func focusContainment(_ mode: FocusContainment) -> Panel<ID, Content> {
    Panel(id: id, containment: mode, content: content)
  }
}

extension View {
  /// Wraps `self` in a Panel with an explicit identity.
  public func panel<PanelID: Hashable & Sendable>(
    id: PanelID
  ) -> Panel<PanelID, Self> {
    Panel(id: id, containment: .open, content: self)
  }

  /// Wraps `self` in a Panel whose identity is derived from the
  /// structural identity path at the call site. Derived from the
  /// structural-identity path at the call site; stable across
  /// re-resolves of the same view hierarchy.
  ///
  /// Use when Panel identity can be derived from structural position
  /// rather than a user-meaningful value. For identity that survives
  /// view-tree refactoring or refers to domain data, prefer
  /// `.panel(id:)`.
  public func panel() -> Panel<AnyID, Self> {
    guard let scope = currentAuthoringContext() else {
      preconditionFailure(
        ".panel() requires an authoring context — call it inside a View's body, or use .panel(id:) with an explicit identity."
      )
    }
    return Panel(id: AnyID(scope.structuralIdentity), containment: .open, content: self)
  }
}
