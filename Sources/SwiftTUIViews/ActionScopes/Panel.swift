public import SwiftTUICore

/// Controls how focus enters a Panel's descendants.
public enum FocusContainment: Sendable {
  /// Default: Tab reaches focusable descendants of the Panel.
  case open
  /// Panel is the focus stop. Tab skips the focusable descendants of the Panel.
  /// A future design will add a drill-in mechanism.
  case sealed
}

/// A rectangular consumer-controlled area that conforms to
/// `ActionScope`.
///
/// Panel has no default UI chrome. Visual treatment is the consumer's
/// responsibility through standard modifiers, such as `.border`, `.background`, and `.padding`.
///
/// A Panel is a *container* that hosts commands and chrome. It is not a control.
/// It is a focus *scope*, so commands and focused values resolve along its chain.
/// It is not a focus *target*. Tab passes through it to the focusable item leaves inside.
/// The Panel itself is never focused.
/// Its commands activate through the active and visible context.
/// Focusing the container does not activate them.
/// This behavior matches SwiftUI toolbars and commands in system regions.
///
/// Pair with `.keyCommand(...)`, `.paletteCommand(...)`, or
/// `.focusContainment(_:)` to configure.
public struct Panel<ID: Hashable & Sendable, Content: View>: PrimitiveView, ActionScope,
  ResolvableView
{
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
    // A Panel is a command host (Role A): a focus scope, not a focus target.
    // It hoists commands/chrome and bounds a scope, but does not participate in
    // top-level focus, so Tab passes through to item leaves. `.sealed` adds a
    // hard stop that suppresses descendant focus too.
    var metadata = focusStructureMetadata(scopeBoundary: true)
    metadata.isCommandHost = true
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

  /// Wraps `self` in a Panel whose identity comes from the structural identity path at the call site.
  /// This identity is stable across
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
    return Panel(id: AnyID(scope.structuralPath), containment: .open, content: self)
  }
}
