public import SwiftTUICore

/// Declares where a toolbar strip is placed relative to its scope's
/// content.
public enum ToolbarPlacement: Sendable {
  case top
  case bottom
}

/// Style protocol for toolbars declared on ActionScopes.
///
/// Implementations control the layout of toolbar items (horizontal,
/// wrapped, top vs. bottom placement) via the framework's existing
/// `Layout` protocol. The strip runs `itemLayout` to arrange the
/// toolbar items; the host composes the strip above or below its
/// content per `placement`.
public protocol ToolbarStyle: Sendable {
  associatedtype ItemLayout: Layout
  var itemLayout: ItemLayout { get }
  var placement: ToolbarPlacement { get }
}

/// A top-placed toolbar that lays items out horizontally with a
/// single-cell gap.
public struct DefaultTopToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .top }

  public init() {}
}

/// A bottom-placed toolbar that lays items out horizontally with a
/// single-cell gap.
public struct DefaultBottomToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .bottom }

  public init() {}
}

extension ToolbarStyle where Self == DefaultTopToolbarStyle {
  public static var defaultTop: DefaultTopToolbarStyle { .init() }
}

extension ToolbarStyle where Self == DefaultBottomToolbarStyle {
  public static var defaultBottom: DefaultBottomToolbarStyle { .init() }
}

extension ActionScope where Self: View {
  /// Declares that this scope has a toolbar. Toolbar items contributed
  /// by descendant views via `.toolbarItem(_:)` are absorbed at this
  /// scope and rendered as a horizontal strip above or below the
  /// scope's content per `style.placement`.
  @MainActor
  public func toolbar<S: ToolbarStyle>(
    style: S
  ) -> some View & ActionScope {
    modifier(
      ToolbarModifier(
        style: style
      )
    )
  }
}

/// Primitive lowering for `.toolbar(style:)`. Reads accumulated
/// `ToolbarItemsPreferenceKey` contributions off the resolved content
/// node, composes a toolbar strip next to the content using
/// `style.itemLayout` + `style.placement`, and clears the preference
/// so items do not bubble past this scope.
public struct ToolbarModifier<S: ToolbarStyle>: PrimitiveViewModifier, Sendable {
  package let style: S

  package init(style: S) {
    self.style = style
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    // Resolve the wrapped ActionScope at the ToolbarHost's own
    // identity. The scope root must remain the real graph node so
    // retained snapshot rebuilds recurse through the current
    // scope-root commit instead of a stale child snapshot that never
    // learned about the toolbar strip.
    let base = content.resolve(in: context)
    let items = base.preferenceValues[ToolbarItemsPreferenceKey.self]

    guard !items.isEmpty else {
      // No contributions — preserve the base node unchanged, but still
      // clear the preference so ancestor hosts do not re-absorb any
      // stray items. (Empty in practice, but the clear is cheap and
      // keeps the invariant uniform.)
      var passthrough = base
      passthrough.preferenceValues[ToolbarItemsPreferenceKey.self] = []
      return [passthrough]
    }

    let stripView = ToolbarItemsStrip(items: items, style: style)
    let stripNode = stripView.resolve(
      in: context.child(component: .named("toolbar-strip"))
    )

    // Keep the scope boundary on `base` so toolbar-focus inherits the
    // ActionScope's identity. Install the safe-area reclaiming step on
    // the scope root, and move the actual toolbar composition into a
    // real child view so retained snapshot rebuilds recurse through a
    // committed toolbar subtree instead of a stale injected copy.
    let toolbarNode = ToolbarScopeNode(
      contentChildren: base.children,
      contentLayoutBehavior: base.layoutBehavior,
      stripNode: stripNode,
      edge: toolbarEdge,
      alignment: toolbarAlignment
    ).resolve(
      in: context.child(component: .named("toolbar-scope"))
    )

    var scopeWithStrip = base
    scopeWithStrip.children = [toolbarNode]
    scopeWithStrip.layoutBehavior = .safeAreaIgnoring(
      context.environmentValues.safeAreaInsets.masked(to: toolbarEdgeSet)
    )
    // Clear the preference at this scope boundary so absorbed items
    // do not re-bubble to ancestor toolbar hosts.
    scopeWithStrip.preferenceValues[ToolbarItemsPreferenceKey.self] = []

    return [scopeWithStrip]
  }

  private var toolbarEdge: Edge {
    switch style.placement {
    case .top: .top
    case .bottom: .bottom
    }
  }

  private var toolbarAlignment: Alignment {
    switch style.placement {
    case .top: .top
    case .bottom: .bottom
    }
  }

  private var toolbarEdgeSet: Edge.Set {
    switch style.placement {
    case .top: .top
    case .bottom: .bottom
    }
  }

}

private struct ToolbarScopeNode: PrimitiveView, ResolvableView {
  let contentChildren: [ResolvedNode]
  let contentLayoutBehavior: LayoutBehavior
  let stripNode: ResolvedNode
  let edge: Edge
  let alignment: Alignment

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let contentNode = ToolbarContentNode(
      children: contentChildren,
      layoutBehavior: contentLayoutBehavior
    ).resolve(
      in: context.child(component: .named("content"))
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ToolbarScope"),
        children: [contentNode, stripNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .safeAreaInset(
          edge: edge,
          alignment: alignment,
          spacing: 0,
          safeArea: .zero
        )
      )
    ]
  }
}

private struct ToolbarContentNode: PrimitiveView, ResolvableView {
  let children: [ResolvedNode]
  let layoutBehavior: LayoutBehavior

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ToolbarContent"),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layoutBehavior
      )
    ]
  }
}

/// Arranges the contributed toolbar items using the style's item
/// layout. Each item is rendered as a Button whose label is the item
/// title; when an icon is present, the title is prefixed by the icon
/// with a single-cell gap.
///
/// The strip claims the full horizontal width of its host and paints a
/// chrome-surface background behind it so the toolbar reads as a
/// distinct bar rather than a floating row of buttons flush against
/// the content.
private struct ToolbarItemsStrip<S: ToolbarStyle>: PrimitiveView, ResolvableView {
  let items: [ToolbarItemConfig]
  let style: S

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let layout = style.itemLayout
    let content = layout {
      ForEach(items.indices, id: \.self) { index in
        ToolbarItemButton(config: items[index])
      }
    }
    // Frame-then-background so the fill covers the full row width, not
    // just the items' natural extent. Items stay flush-leading; the
    // Rectangle fills the trailing slack.
    let strip =
      content
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        Rectangle().fill(AnyShapeStyle(.terminalSurfaceBackground))
      }
    return [strip.resolve(in: context)]
  }
}

private struct ToolbarItemButton: View {
  let config: ToolbarItemConfig

  var body: some View {
    Button(action: config.action) {
      if let icon = config.icon {
        HStack(spacing: 1) {
          icon
          Text(config.title)
        }
      } else {
        Text(config.title)
      }
    }
    .systemHint(config.systemHint)
    .disabled(!config.isEnabled)
  }
}
