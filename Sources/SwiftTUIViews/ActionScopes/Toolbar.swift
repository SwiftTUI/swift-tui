public import SwiftTUICore

// The toolbar style vocabulary — `ToolbarStyle`, `ToolbarPlacement`, and the
// built-in `Default*ToolbarStyle` conformances — lives in `ToolbarStyle.swift`.

extension ActionScope where Self: View {
  /// Declares that this scope has a toolbar.
  /// This scope absorbs toolbar items that descendant views supply through `.toolbarItem(_:)`.
  /// It shows them as a horizontal strip above or below the content according to the
  /// nearest `toolbarStyle(_:)` value's placement.
  @MainActor
  public func toolbar() -> some View & ActionScope {
    modifier(ToolbarModifier())
  }
}

extension ActionScope where Self: View {
  /// Sets the toolbar style for this scope's subtree while preserving the
  /// `ActionScope` conformance, so a `toolbar()` declaration can follow.
  ///
  /// `environment(_:_:)` erases to `some View`, which would drop the
  /// conformance, so this applies the same modifier directly —
  /// `ModifiedContent` conditionally conforms to `ActionScope`.
  @MainActor
  public func toolbarStyle(
    _ style: AnyToolbarStyle
  ) -> some View & ActionScope {
    modifier(
      EnvironmentWritingModifier(
        keyPath: \.toolbarStyle,
        value: style
      )
    )
  }

  @MainActor
  public func toolbarStyle<S: ToolbarStyle>(
    _ style: S
  ) -> some View & ActionScope {
    toolbarStyle(AnyToolbarStyle(style))
  }
}

/// The primitive implementation of `.toolbar()`.
/// It reads accumulated `ToolbarItemsPreferenceKey` contributions from the resolved content node.
/// Then it uses the nearest `toolbarStyle` value's item layout and placement to compose a
/// toolbar strip next to the content.
/// It clears the preference so items do not continue past this scope.
public struct ToolbarModifier: PrimitiveViewModifier, Sendable {
  package init() {}

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let style = context.environmentValues.toolbarStyle
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

  let content = node.toolbarHostContent()
  let items =
    content.children.flatMap(toolbarItemsForNearestHost(in:))
    + node.directToolbarItemContributions
  let reconciled = descriptor.reconcile(node, items)
  changed = changed || reconciled != node
  requiresRelayout = requiresRelayout || !reconciled.isEquivalentForPlacement(to: node)
  return (reconciled, changed, requiresRelayout)
}

/// Reconstructs the complete preference input for the nearest toolbar host
/// from authored contribution metadata. A retained graph snapshot rebuild can
/// replace children without re-running an unchanged contribution modifier;
/// its reduced `preferenceValues` cache is therefore not an authoritative
/// source for node-local items. Nested hosts are absorption boundaries and
/// rebuild their own item lists independently.
private func toolbarItemsForNearestHost(
  in node: ResolvedNode
) -> [ToolbarItemConfig] {
  if node.layoutMetadata.layoutValue(
    for: toolbarLatePreferenceHostMetadataKey,
    as: ToolbarLatePreferenceHostDescriptor.self
  ) != nil {
    return []
  }

  return
    node.children.flatMap(toolbarItemsForNearestHost(in:))
    + node.directToolbarItemContributions
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
  fileprivate func withToolbarLatePreferenceHost(
    style: AnyToolbarStyle,
    context: ResolveContext
  ) -> ResolvedNode {
    var copy = self
    let debugValue = "\(style.snapshotLabel):\(style.placement)"
    // The reconcile below runs in the late-preference stage, off the resolve
    // stack, so `ResolveLifetimeScopeContext.current` is nil there and every
    // node it mints (`…/toolbar-scope` and its interior) is reported to no
    // scope and left with NO lifetime anchor at all — stranded and unreachable
    // the moment its declaring host stops committing it (F91). Capture the
    // declaring host here, where `ViewNodeContext.current` still names it, and
    // reinstall it around the reconcile exactly as delayed indexed-child
    // realization does for its own out-of-stack mints.
    let latePreferenceHost = ViewNodeContext.current
    copy.layoutMetadata = copy.layoutMetadata.settingLayoutValue(
      ToolbarLatePreferenceHostDescriptor(
        debugValue: debugValue,
        reconcile: { [weak latePreferenceHost] node, items in
          let reconcile = {
            node.reconciledToolbarHost(
              items: items,
              style: style,
              context: context
            )
          }
          guard let viewGraph = context.viewGraph else {
            return reconcile()
          }
          return viewGraph.withCapturedResolveLifetimeScope(
            hostedBy: latePreferenceHost,
            reconcile
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
  fileprivate func reconciledToolbarHost(
    items: [ToolbarItemConfig],
    style: AnyToolbarStyle,
    context: ResolveContext
  ) -> ResolvedNode {
    let context = context.applyingCurrentFrameResolveInputs()
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

    let stripContext = context.child(component: .named("toolbar-strip"))
    let strip = resolvedToolbarItemsStrip(
      items: items,
      style: style,
      context: stripContext
    )
    let stripNode = strip.node
    // This reconcile runs in the late-preference stage, outside any dirty
    // plan. When the ITEM SET changes (the content changed under a frontier
    // that is a sibling of `…/toolbar-strip` beneath this scope) the host's
    // graph node still applies last frame's strip: the departed item's nodes
    // stay live (the barrier defers their teardown until the host next
    // applies), their action registrations stay published, and the
    // presented strip lags until some later root frame. Ask for a follow-up
    // frame rooted at the host so it re-applies through the normal dirty
    // plan; teardown, registrations, and damage then all see the new strip.
    // The follow-up frame finds the new signature already cached, so this
    // cannot re-arm itself. A same-frame install was tried and rejected: the
    // tail's first layout pass has already visited the old strip's
    // style-body islands, so a cascade from the host spares them as a
    // decapitated strand the barrier cannot reclaim (the toolbar-strip item
    // churn strand). And the trigger is the SIGNATURE, never a bare cache
    // miss: a focused text field moves the environment every frame, so a
    // miss-based trigger re-armed the follow-up forever.
    if strip.itemSetChanged {
      context.invalidationProxy?.invalidator?.requestInvalidation(of: [identity])
    }

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
    // `fillsProposal: true` is load-bearing: the strip pins to the far edge
    // of whatever region this scope claims, so a content-hugging scope would
    // park a bottom toolbar directly under short content instead of at the
    // bottom of the terminal.
    scopeWithStrip.layoutBehavior = .safeAreaIgnoring(
      context.environmentValues.safeAreaInsets.masked(to: toolbarEdgeSet(for: style)),
      fillsProposal: true
    )
    // Clear the preference at this scope boundary so absorbed items
    // do not re-bubble to ancestor toolbar hosts while preserving
    // sibling preferences attached directly to the scope node.
    scopeWithStrip.preferenceValues = absorbedPreferences

    return scopeWithStrip
  }

  fileprivate func toolbarHostContent() -> (
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

private func toolbarEdge(
  for style: AnyToolbarStyle
) -> Edge {
  switch style.placement {
  case .top: .top
  case .bottom: .bottom
  }
}

private func toolbarAlignment(
  for style: AnyToolbarStyle
) -> Alignment {
  switch style.placement {
  case .top: .top
  case .bottom: .bottom
  }
}

private func toolbarEdgeSet(
  for style: AnyToolbarStyle
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

private let toolbarStripReuseCacheNamespace = "SwiftTUI.toolbar-strip"

/// The strip subtree plus whether its item-set/style signature differs from
/// the one the reuse cache last stored for this strip — i.e. a committed
/// strip was REPLACED by a different item set. A plain cache miss (first
/// frame, environment or transaction drift, a suppressed-reuse frame) is not
/// a replacement and must not re-arm the host follow-up frame.
private struct ResolvedToolbarStrip {
  var node: ResolvedNode
  var itemSetChanged: Bool
}

@MainActor
private func resolvedToolbarItemsStrip(
  items: [ToolbarItemConfig],
  style: AnyToolbarStyle,
  context: ResolveContext
) -> ResolvedToolbarStrip {
  guard let signature = ToolbarStripSignature(items: items, style: style) else {
    // No reuse signature (a custom layout without measurement/placement
    // signatures): the strip resolves fresh every frame and carries no
    // comparable item-set identity — never re-arm the host follow-up here.
    return ResolvedToolbarStrip(
      node: ToolbarItemsStrip(items: items, style: style).resolve(in: context),
      itemSetChanged: false
    )
  }

  let previousSignature = context.viewGraph?.resolvedNodeReuseCacheSignature(
    namespace: toolbarStripReuseCacheNamespace,
    owner: context.identity
  )
  let itemSetChanged =
    previousSignature != nil && previousSignature != signature.cacheSignature
  if !context.effectiveSuppressesRetainedReuse(at: context.identity),
    let reused = context.viewGraph?.cachedReusableResolvedNode(
      namespace: toolbarStripReuseCacheNamespace,
      owner: context.identity,
      signature: signature.cacheSignature,
      environment: context.environment,
      transaction: context.transaction
    )
  {
    // The cached tree's restored handlers close over the RESOLVE-TIME item
    // closures, so the reuse leg must re-point them at the current items.
    // The target identities are discovered from the reused subtree's own
    // node records — the same records `restoreRuntimeRegistrations` replays
    // — so they track the strip's real lowering by construction (F175: a
    // hand-mirrored identity mint silently stranded the refresh on any
    // lowering change). Disabled items never register an action (Button
    // gates registration on `isEnabled`) and the cache signature includes
    // `isEnabled`, so the discovered identities pair positionally with the
    // enabled items; on any count mismatch fall through to a fresh resolve
    // instead of refreshing blindly.
    let enabledItems = items.filter(\.isEnabled)
    let refreshIdentities =
      context.viewGraph?.actionRegistrationIdentities(inReusedSubtree: reused) ?? []
    if refreshIdentities.count == enabledItems.count {
      context.viewGraph?.recordReusedSubtree(
        reused,
        invalidator: context.invalidationProxy?.invalidator,
        retained: true
      )
      context.viewGraph?.restoreRuntimeRegistrations(
        for: reused,
        into: context.runtimeRegistrations
      )
      refreshToolbarItemActionRegistrations(enabledItems, at: refreshIdentities, in: context)
      context.recordResolvedReuse(count: reused.subtreeNodeCount)
      var structurallyStamped = reused
      structurallyStamped.structuralPath = context.structuralPath
      return ResolvedToolbarStrip(node: structurallyStamped, itemSetChanged: false)
    }
  }

  let resolved = ToolbarItemsStrip(items: items, style: style).resolve(in: context)
  context.viewGraph?.storeResolvedNodeReuseCache(
    namespace: toolbarStripReuseCacheNamespace,
    owner: context.identity,
    signature: signature.cacheSignature,
    node: resolved
  )
  return ResolvedToolbarStrip(node: resolved, itemSetChanged: itemSetChanged)
}

@MainActor
private func refreshToolbarItemActionRegistrations(
  _ enabledItems: [ToolbarItemConfig],
  at identities: [Identity],
  in stripContext: ResolveContext
) {
  for (item, identity) in zip(enabledItems, identities) {
    stripContext.viewGraph?.refreshActionRegistration(
      identity: identity,
      handler: {
        item.action()
        return true
      },
      followUpInvalidationIdentity: item.sourceIdentity,
      in: stripContext.localActionRegistry
    )
  }
}

private struct ToolbarStripSignature: Hashable {
  var styleType: String
  var placement: String
  var layout: String
  var items: [ToolbarStripItemSignature]

  init?(
    items: [ToolbarItemConfig],
    style: AnyToolbarStyle
  ) {
    // The signature comes from the *concrete* layout, captured when the
    // style was erased — see `AnyToolbarStyleBox.layoutSignature`.
    guard let layout = style.layoutSignature else {
      return nil
    }
    styleType = style.snapshotLabel
    placement = toolbarPlacementSignature(style.placement)
    self.layout = layout
    self.items = items.map(ToolbarStripItemSignature.init(item:))
  }

  var cacheSignature: String {
    String(reflecting: self)
  }
}

private struct ToolbarStripItemSignature: Hashable {
  var title: String
  var icon: ToolbarStripIconSignature?
  var position: String
  var isEnabled: Bool
  var systemHint: String?

  init(item: ToolbarItemConfig) {
    title = item.title
    icon = item.icon.map(ToolbarStripIconSignature.init(icon:))
    position = toolbarItemPositionSignature(item.position)
    isEnabled = item.isEnabled
    systemHint = item.systemHint
  }
}

private struct ToolbarStripIconSignature: Hashable {
  var source: ImageSource
  var isResizable: Bool
  var scalingMode: String

  init(icon: Image) {
    source = icon.source
    isResizable = icon.isResizable
    scalingMode = icon.scalingMode.rawValue
  }
}

func toolbarLayoutSignature<L: Layout>(
  _ layout: L
) -> String? {
  let layoutType = String(reflecting: L.self)
  if let builtinLayout = layout as? any BuiltinLayoutBehaviorProviding {
    return "builtin:\(layoutType):\(String(reflecting: builtinLayout.builtinLayoutBehavior))"
  }
  guard
    let measurementSignature = layout.measurementReuseSignature,
    let placementSignature = layout.placementReuseSignature
  else {
    return nil
  }

  return "signed:\(layoutType):measure:\(measurementSignature):"
    + "place:\(placementSignature)"
}

private func toolbarPlacementSignature(
  _ placement: ToolbarPlacement
) -> String {
  switch placement {
  case .top: "top"
  case .bottom: "bottom"
  }
}

private func toolbarItemPositionSignature(
  _ position: ToolbarItemConfig.Position
) -> String {
  switch position {
  case .top: "top"
  case .bottom: "bottom"
  case .automatic: "automatic"
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
    // The hosted children are values captured from the frame's resolve, not
    // re-resolved here — a capture-host injection. The late-preference
    // reconcile applies this wrapper while the async frame protocol has the
    // prepared graph suspended back to baseline, so the captured stamps can
    // pair against superseded live nodes. Withdraw the stamp claims at every
    // level so the apply's restamping walk stays on the slow (verifying)
    // path instead of fast-skipping over foreign stamps.
    var injectedChildren = children
    for index in injectedChildren.indices {
      injectedChildren[index].withdrawSubtreeRuntimeNodeIDStampsRecursively()
    }
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ToolbarContent"),
        children: injectedChildren,
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
private struct ToolbarItemsStrip: PrimitiveView, ResolvableView {
  let items: [ToolbarItemConfig]
  let style: AnyToolbarStyle

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
