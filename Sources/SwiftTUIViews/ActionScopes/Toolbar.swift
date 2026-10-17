public import SwiftTUICore

// The toolbar style vocabulary — `ToolbarStyle`, `ToolbarPlacement`, and the
// built-in `Default*ToolbarStyle` conformances — lives in `ToolbarStyle.swift`.

extension ActionScope where Self: View {
  /// Declares that this scope has a toolbar.
  /// This scope absorbs toolbar items that descendant views supply through `.toolbarItem(_:)`.
  /// Explicit item positions create strips at their requested edge. Automatic
  /// items follow the nearest `toolbarStyle(_:)` value's placement.
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
  ///
  /// The style is stored in the environment for the subtree, so the nearest
  /// modifier above a ``ToolbarModifier`` scope wins. It affects only the strip
  /// a `toolbar()` scope composes: its item layout and whether the strip sits
  /// above or below the content. The built-ins are
  /// ``AnyToolbarStyle/defaultTop`` and ``AnyToolbarStyle/defaultBottom``; the
  /// environment default is ``AnyToolbarStyle/defaultTop``, so writing it
  /// explicitly changes nothing.
  ///
  /// - Parameter style: The erased style to store for the subtree.
  /// - Returns: The scope, still an `ActionScope`, with the style in force
  ///   below it.
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

  /// Sets the toolbar style for this scope's subtree from a concrete style,
  /// preserving the `ActionScope` conformance.
  ///
  /// Equivalent to wrapping `style` in ``AnyToolbarStyle`` and calling the
  /// other overload, so the same nearest-modifier-wins rule applies.
  ///
  /// - Parameter style: The concrete style to store for the subtree.
  /// - Returns: The scope, still an `ActionScope`, with the style in force
  ///   below it.
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
public struct ToolbarModifier: IterativePrimitiveViewModifier, Sendable {
  package init() {}

  package func makeResolveWork<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let style = context.environmentValues.toolbarStyle
    // Resolve the wrapped ActionScope at the ToolbarHost's own
    // identity. The scope root must remain the real graph node so
    // retained snapshot rebuilds recurse through the current
    // scope-root commit instead of a stale child snapshot that never
    // learned about the toolbar strip.
    return content.resolveWork(in: context).flatMap { completed in
      let base = completed
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
        return .value([passthrough])
      }

      return hostedBase.reconciledToolbarHostWork(
        items: items,
        style: style,
        context: context
      ).map { [$0] }

    }
  }

}

private enum ToolbarLatePreferenceHostKey {}

private let toolbarLatePreferenceHostMetadataKey = ObjectIdentifier(
  ToolbarLatePreferenceHostKey.self
)

private struct ToolbarLatePreferenceHostDescriptor: Sendable, Equatable {
  let debugValue: String
  let owner: StateOwnerHandle?
  let identity: Identity
  let structuralPath: StructuralPath
  let environment: EnvironmentSnapshot
  let transaction: TransactionSnapshot
  let style: AnyToolbarStyle
  let reconcile: @MainActor @Sendable (ResolvedNode, [ToolbarItemConfig]) -> ResolvedNode

  static func == (lhs: Self, rhs: Self) -> Bool {
    // The callback is rebuilt from these captures, then rebased to current
    // frame inputs when invoked. Opaque custom styles still deny reuse.
    lhs.owner == rhs.owner && lhs.identity == rhs.identity
      && lhs.structuralPath == rhs.structuralPath && lhs.environment == rhs.environment
      && lhs.transaction == rhs.transaction && lhs.style.isEqualForReuse(to: rhs.style)
  }
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
        owner: latePreferenceHost?.stateOwnerHandle,
        identity: context.identity,
        structuralPath: context.structuralPath,
        environment: context.environment,
        transaction: context.transaction,
        style: style,
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
  fileprivate func reconciledToolbarHostWork(
    items: [ToolbarItemConfig],
    style: AnyToolbarStyle,
    context: ResolveContext
  ) -> ResolveWork<ResolvedNode> {
    let context = context.applyingCurrentFrameResolveInputs()
    let content = toolbarHostContent()

    var absorbedPreferences = preferenceValues
    absorbedPreferences[ToolbarItemsPreferenceKey.self] = []

    let topItems = items.filter { item in
      switch item.position {
      case .top: true
      case .bottom: false
      case .automatic: style.placement == .top
      }
    }
    let bottomItems = items.filter { item in
      switch item.position {
      case .top: false
      case .bottom: true
      case .automatic: style.placement == .bottom
      }
    }
    // The style owns item layout and the automatic edge; explicit positions
    // partition contributions into independent strips with stable identities.
    let topName: StaticString = style.placement == .top ? "toolbar-strip" : "toolbar-strip-top"
    let bottomName: StaticString =
      style.placement == .bottom ? "toolbar-strip" : "toolbar-strip-bottom"
    return resolvedToolbarItemsStripWork(
      items: topItems, style: style, context: context.child(component: .named(topName))
    ).flatMap { top in
      resolvedToolbarItemsStripWork(
        items: bottomItems, style: style, context: context.child(component: .named(bottomName))
      ).flatMap { bottom in
        // Late reconciliation cannot retire the previous graph subtree until
        // the host re-applies. A signature change schedules that one follow-up;
        // empty-strip signatures also track removal, without re-arming it.
        if top.itemSetChanged || bottom.itemSetChanged {
          context.invalidationProxy?.invalidator?.requestInvalidation(of: [identity])
        }
        guard top.node != nil || bottom.node != nil else {
          var passthrough = self
          passthrough.children = content.children
          passthrough.layoutBehavior = content.layoutBehavior
          passthrough.preferenceValues = absorbedPreferences
          return .value(passthrough)
        }
        return ToolbarScopeNode(
          contentChildren: content.children, contentLayoutBehavior: content.layoutBehavior,
          topStrip: top.node, bottomStrip: bottom.node
        ).resolveWork(in: context.child(component: .named("toolbar-scope"))).map { toolbarNode in
          var scopeWithStrips = self
          scopeWithStrips.children = [toolbarNode]
          var edges: Edge.Set = []
          if top.node != nil { edges.insert(.top) }
          if bottom.node != nil { edges.insert(.bottom) }
          scopeWithStrips.layoutBehavior = .safeAreaIgnoring(
            context.environmentValues.safeAreaInsets.masked(to: edges), fillsProposal: true)
          scopeWithStrips.preferenceValues = absorbedPreferences
          return scopeWithStrips
        }
      }
    }
  }

  @MainActor
  fileprivate func reconciledToolbarHost(
    items: [ToolbarItemConfig], style: AnyToolbarStyle, context: ResolveContext
  ) -> ResolvedNode {
    reconciledToolbarHostWork(items: items, style: style, context: context).run()
  }

  fileprivate func toolbarHostContent() -> (
    children: [ResolvedNode],
    layoutBehavior: LayoutBehavior,
    hasHostedToolbar: Bool
  ) {
    guard children.count == 1, isKind(children[0].kind, named: "ToolbarScope") else {
      return (children, layoutBehavior, false)
    }
    var node = children[0]
    while isKind(node.kind, named: "ToolbarScope") || isKind(node.kind, named: "ToolbarInset") {
      guard let child = node.children.first else { return (children, layoutBehavior, false) }
      node = child
    }
    guard isKind(node.kind, named: "ToolbarContent") else {
      return (children, layoutBehavior, false)
    }
    return (node.children, node.layoutBehavior, true)
  }
}

private func isKind(_ kind: NodeKind, named name: String) -> Bool {
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
  var node: ResolvedNode?
  var itemSetChanged: Bool
}

@MainActor
private func resolvedToolbarItemsStripWork(
  items: [ToolbarItemConfig],
  style: AnyToolbarStyle,
  context: ResolveContext
) -> ResolveWork<ResolvedToolbarStrip> {
  if items.isEmpty {
    let previous = context.viewGraph?.resolvedNodeReuseCacheSignature(
      namespace: toolbarStripReuseCacheNamespace, owner: context.identity)
    let emptySignature = "empty-toolbar-strip"
    // Store only the absence signature. No view, handlers or paint is mounted
    // for an empty edge; the marker is never restored as a resolved subtree.
    context.viewGraph?.storeResolvedNodeReuseCache(
      namespace: toolbarStripReuseCacheNamespace, owner: context.identity,
      signature: emptySignature,
      node: ResolvedNode(identity: context.identity, kind: .view("EmptyToolbarStrip")))
    return .value(
      ResolvedToolbarStrip(
        node: nil, itemSetChanged: previous != nil && previous != emptySignature))
  }
  guard let signature = ToolbarStripSignature(items: items, style: style) else {
    // No reuse signature (a custom layout without measurement/placement
    // signatures): the strip resolves fresh every frame and carries no
    // comparable item-set identity — never re-arm the host follow-up here.
    return ToolbarItemsStrip(items: items, style: style).resolveWork(in: context).map {
      ResolvedToolbarStrip(node: $0, itemSetChanged: false)
    }
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
      return .value(ResolvedToolbarStrip(node: structurallyStamped, itemSetChanged: false))
    }
  }

  return ToolbarItemsStrip(items: items, style: style).resolveWork(in: context).map { resolved in
    context.viewGraph?.storeResolvedNodeReuseCache(
      namespace: toolbarStripReuseCacheNamespace,
      owner: context.identity,
      signature: signature.cacheSignature,
      node: resolved
    )
    return ResolvedToolbarStrip(node: resolved, itemSetChanged: itemSetChanged)
  }
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
      // sourceIdentity locates the contribution, not the body that authored
      // its action. Untracked writes need the runtime's root backstop.
      followUpInvalidationIdentity: nil,
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
  let topStrip: ResolvedNode?
  let bottomStrip: ResolvedNode?

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    makeResolveWork(in: context).run()
  }

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    ToolbarContentNode(children: contentChildren, layoutBehavior: contentLayoutBehavior)
      .resolveWork(in: context.child(component: .named("content"))).flatMap { content in
        let inner: ResolveWork<ResolvedNode>
        if let topStrip, bottomStrip != nil {
          inner = ToolbarInsetNode(content: content, strip: topStrip, edge: .top)
            .resolveWork(in: context.child(component: .named("top-inset")))
        } else {
          inner = .value(content)
        }
        return inner.map { content in
          let edge: Edge = bottomStrip == nil ? .top : .bottom
          let strip = bottomStrip ?? topStrip
          return [
            ResolvedNode(
              identity: context.identity, kind: .view("ToolbarScope"),
              children: [content] + (strip.map { [$0] } ?? []),
              environmentSnapshot: context.environment, transactionSnapshot: context.transaction,
              layoutBehavior: .safeAreaInset(
                edge: edge, alignment: edge == .top ? .top : .bottom, spacing: 0, safeArea: .zero)
            )
          ]
        }
      }
  }
}

private struct ToolbarInsetNode: PrimitiveView, ResolvableView {
  let content: ResolvedNode
  let strip: ResolvedNode
  let edge: Edge

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      ResolvedNode(
        identity: context.identity, kind: .view("ToolbarInset"), children: [content, strip],
        environmentSnapshot: context.environment, transactionSnapshot: context.transaction,
        layoutBehavior: .safeAreaInset(
          edge: edge, alignment: edge == .top ? .top : .bottom, spacing: 0, safeArea: .zero)
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
    makeResolveWork(in: context).run()
  }

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
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
    return strip.resolveWork(in: context).map { resolved in
      // Fresh buttons are authored by ToolbarItemButton, whose identity is
      // also below the contributor's body. Apply the same action backstop as
      // the reuse path so the next activation cannot strand untracked writes.
      let enabledItems = items.filter(\.isEnabled)
      let identities =
        context.viewGraph?.actionRegistrationIdentities(inReusedSubtree: resolved) ?? []
      if identities.count == enabledItems.count {
        refreshToolbarItemActionRegistrations(enabledItems, at: identities, in: context)
      }
      return [resolved]
    }
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
