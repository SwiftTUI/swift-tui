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
public struct Panel<ID: Hashable & Sendable, Content: View>: View, ActionScope {
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

  public var body: some View {
    PanelBody(id: id, containment: containment, content: content)
  }
}

private struct PanelBody<ID: Hashable & Sendable, Content: View>: View, ResolvableView {
  let id: ID
  let containment: FocusContainment
  let content: Content

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let childNode = content.resolve(in: context.child(component: .named("content")))
    var metadata = focusStructureMetadata(scopeBoundary: true)
    metadata.isFocusable = true
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

extension View {
  /// Wraps `self` in a Panel with an explicit identity.
  public func panel<PanelID: Hashable & Sendable>(
    id: PanelID
  ) -> Panel<PanelID, Self> {
    Panel(id: id, containment: .open, content: self)
  }
}
