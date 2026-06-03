public import SwiftTUICore

// The toolbar style vocabulary — `ToolbarStyle`, `ToolbarPlacement`, and the
// built-in `Default*ToolbarStyle` conformances — lives in `ToolbarStyle.swift`.

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
    let hostedBase = base.withToolbarLatePreferenceHost(
      style: style,
      context: context
    )

    guard !items.isEmpty else {
      // No contributions — preserve the base node unchanged, but still
      // clear the preference so ancestor hosts do not re-absorb any
      // stray items. (Empty in practice, but the clear is cheap and
      // keeps the invariant uniform.)
      var passthrough = hostedBase
      passthrough.preferenceValues[ToolbarItemsPreferenceKey.self] = []
      return [passthrough]
    }

    return [
      hostedBase.reconciledToolbarHost(
        items: items,
        style: style,
        context: context
      )
    ]
  }

}

private enum ToolbarLatePreferenceHostKey {}

private let toolbarLatePreferenceHostMetadataKey = ObjectIdentifier(
  ToolbarLatePreferenceHostKey.self
)

private struct ToolbarLatePreferenceHostDescriptor: Sendable {
  let debugValue: String
  let reconcile: @MainActor @Sendable (ResolvedNode, [ToolbarItemConfig]) -> ResolvedNode
}

package struct LatePreferenceReconciliationOutput {
  package var resolved: ResolvedNode
  package var changed: Bool
  package var requiresRelayout: Bool

  package init(
    resolved: ResolvedNode,
    changed: Bool,
    requiresRelayout: Bool
  ) {
    self.resolved = resolved
    self.changed = changed
    self.requiresRelayout = requiresRelayout
  }
}

@MainActor
package func reconcileLatePreferenceConsumers(
  in root: ResolvedNode
) -> LatePreferenceReconciliationOutput {
  reconcileToolbarHosts(in: root)
}

@MainActor
private func reconcileToolbarHosts(
  in root: ResolvedNode
) -> LatePreferenceReconciliationOutput {
  let result = reconcileToolbarHostSubtree(root)
  return .init(
    resolved: result.node,
    changed: result.changed,
    requiresRelayout: result.requiresRelayout
  )
}

@MainActor
private func reconcileToolbarHostSubtree(
  _ input: ResolvedNode
) -> (node: ResolvedNode, changed: Bool, requiresRelayout: Bool) {
  guard input.containsToolbarLatePreferenceHost else {
    return (input, false, false)
  }

  var node = input
  var changed = false
  var requiresRelayout = false

  if !node.children.isEmpty {
    var reconciledChildren: [ResolvedNode] = []
    reconciledChildren.reserveCapacity(node.children.count)
    for child in node.children {
      let result = reconcileToolbarHostSubtree(child)
      reconciledChildren.append(result.node)
      changed = changed || result.changed
      requiresRelayout = requiresRelayout || result.requiresRelayout
    }
    node.children = reconciledChildren
  }

  guard
    let descriptor = node.layoutMetadata.layoutValue(
      for: toolbarLatePreferenceHostMetadataKey,
      as: ToolbarLatePreferenceHostDescriptor.self
    )
  else {
    return (node, changed, requiresRelayout)
  }

  let items = node.preferenceValues[ToolbarItemsPreferenceKey.self]
  let reconciled = descriptor.reconcile(node, items)
  changed = changed || reconciled != node
  requiresRelayout = requiresRelayout || !reconciled.isEquivalentForPlacement(to: node)
  return (reconciled, changed, requiresRelayout)
}

extension ResolvedNode {
  fileprivate var containsToolbarLatePreferenceHost: Bool {
    if layoutMetadata.layoutValue(
      for: toolbarLatePreferenceHostMetadataKey,
      as: ToolbarLatePreferenceHostDescriptor.self
    ) != nil {
      return true
    }
    return children.contains { $0.containsToolbarLatePreferenceHost }
  }

  @MainActor
  fileprivate func withToolbarLatePreferenceHost<S: ToolbarStyle>(
    style: S,
    context: ResolveContext
  ) -> ResolvedNode {
    var copy = self
    let debugValue = "\(String(reflecting: S.self)):\(style.placement)"
    copy.layoutMetadata = copy.layoutMetadata.settingLayoutValue(
      ToolbarLatePreferenceHostDescriptor(
        debugValue: debugValue,
        reconcile: { node, items in
          node.reconciledToolbarHost(
            items: items,
            style: style,
            context: context
          )
        }
      ),
      for: toolbarLatePreferenceHostMetadataKey,
      debugName: "toolbar-host",
      debugValue: debugValue
    )
    return copy
  }

  @MainActor
  fileprivate func reconciledToolbarHost<S: ToolbarStyle>(
    items: [ToolbarItemConfig],
    style: S,
    context: ResolveContext
  ) -> ResolvedNode {
    let content = toolbarHostContent()

    guard !items.isEmpty else {
      var passthrough = self
      if !content.hasHostedToolbar {
        passthrough.children = content.children
        passthrough.layoutBehavior = content.layoutBehavior
      }
      passthrough.preferenceValues[ToolbarItemsPreferenceKey.self] = []
      return passthrough
    }

    var absorbedPreferences = preferenceValues
    absorbedPreferences[ToolbarItemsPreferenceKey.self] = []

    let stripNode = ToolbarItemsStrip(items: items, style: style).resolve(
      in: context.child(component: .named("toolbar-strip"))
    )

    // Keep the scope boundary on `base` so toolbar-focus inherits the
    // ActionScope's identity. Install the safe-area reclaiming step on
    // the scope root, and move the actual toolbar composition into a
    // real child view so retained snapshot rebuilds recurse through a
    // committed toolbar subtree instead of a stale injected copy.
    let toolbarNode = ToolbarScopeNode(
      contentChildren: content.children,
      contentLayoutBehavior: content.layoutBehavior,
      stripNode: stripNode,
      edge: toolbarEdge(for: style),
      alignment: toolbarAlignment(for: style)
    ).resolve(
      in: context.child(component: .named("toolbar-scope"))
    )

    var scopeWithStrip = self
    scopeWithStrip.children = [toolbarNode]
    scopeWithStrip.layoutBehavior = .safeAreaIgnoring(
      context.environmentValues.safeAreaInsets.masked(to: toolbarEdgeSet(for: style))
    )
    // Clear the preference at this scope boundary so absorbed items
    // do not re-bubble to ancestor toolbar hosts while preserving
    // sibling preferences attached directly to the scope node.
    scopeWithStrip.preferenceValues = absorbedPreferences

    return scopeWithStrip
  }

  private func toolbarHostContent() -> (
    children: [ResolvedNode],
    layoutBehavior: LayoutBehavior,
    hasHostedToolbar: Bool
  ) {
    guard
      children.count == 1,
      isKind(children[0].kind, named: "ToolbarScope"),
      let contentNode = children[0].children.first,
      isKind(contentNode.kind, named: "ToolbarContent")
    else {
      return (children, layoutBehavior, false)
    }

    return (contentNode.children, contentNode.layoutBehavior, true)
  }

}

private func toolbarEdge<S: ToolbarStyle>(
  for style: S
) -> Edge {
  switch style.placement {
  case .top: .top
  case .bottom: .bottom
  }
}

private func toolbarAlignment<S: ToolbarStyle>(
  for style: S
) -> Alignment {
  switch style.placement {
  case .top: .top
  case .bottom: .bottom
  }
}

private func toolbarEdgeSet<S: ToolbarStyle>(
  for style: S
) -> Edge.Set {
  switch style.placement {
  case .top: .top
  case .bottom: .bottom
  }
}

private func isKind(
  _ kind: NodeKind,
  named name: String
) -> Bool {
  if case .view(let n) = kind, n == name { return true }
  return false
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
    let buttons = VariadicView(items.map(ToolbarItemButton.init(config:)))
    let content = layout {
      buttons
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
    .accessibilityLabel(config.title)
    .disabled(!config.isEnabled)
  }
}
