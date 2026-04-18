public import Core

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

extension ActionScope where Self: View & Sendable {
  /// Declares that this scope has a toolbar. Toolbar items contributed
  /// by descendant views via `.toolbarItem(_:)` are absorbed at this
  /// scope and rendered as a horizontal strip above or below the
  /// scope's content per `style.placement`.
  ///
  /// Items not absorbed here (because no descendant contributed any)
  /// do not change the rendered output.
  @MainActor
  public func toolbar<S: ToolbarStyle>(style: S) -> ToolbarHost<Self, S> {
    ToolbarHost(content: self, style: style)
  }
}

/// The view returned by `.toolbar(style:)`. Reads accumulated
/// `ToolbarItemsPreferenceKey` contributions off the resolved content
/// node, composes a toolbar strip next to the content using
/// `style.itemLayout` + `style.placement`, and clears the preference
/// so items do not bubble past this scope.
public struct ToolbarHost<Content: View & Sendable, S: ToolbarStyle>: View, ResolvableView {
  nonisolated let content: Content
  let style: S

  init(content: Content, style: S) {
    self.content = content
    self.style = style
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseContext = context.child(component: .named("content"))
    let base = content.resolve(in: baseContext)
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

    // Inject the strip as a child of `base` (the underlying
    // ActionScope, typically a Panel) so focus on any toolbar-strip
    // button inherits the scope's identity on its scopePath:
    // palette/key commands registered at the scope stay visible to
    // toolbar focus. Then wrap the reformed scope in a passthrough
    // outer node at `context.identity` so the resolved node's
    // identity matches the identity `resolveView` registered in the
    // ViewGraph at the start of this evaluation.
    //
    // A previous version of this method collapsed the outer wrapper
    // entirely and returned `base` with its identity unchanged. That
    // left the graph holding a node at `context.identity` whose
    // `committed` resolved snapshot had `base.identity`, and
    // `finishEvaluation` re-parented `base`'s subtree under the
    // ToolbarHost's graph node — overwriting the parent pointer that
    // Panel's own graph node had just set. State-change invalidations
    // that walk up via `invalidateAncestorCachedSnapshots` skipped
    // the Panel node, so subsequently-cached ancestor snapshots went
    // stale. The visible symptom was pointer scrolling updating the
    // scroll state internally but the rendered surface only catching
    // up on the next non-scroll event (a click, a keypress, etc.).
    let updatedChildren: [ResolvedNode] =
      switch style.placement {
      case .top: [stripNode] + base.children
      case .bottom: base.children + [stripNode]
      }

    var scopeWithStrip = base
    scopeWithStrip.children = updatedChildren
    scopeWithStrip.layoutBehavior = .stack(
      axis: .vertical,
      spacing: 0,
      horizontalAlignment: .center,
      verticalAlignment: .center
    )
    // Clear the preference at this scope boundary so absorbed items
    // do not re-bubble to ancestor toolbar hosts.
    scopeWithStrip.preferenceValues[ToolbarItemsPreferenceKey.self] = []

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ToolbarHost"),
        children: [scopeWithStrip],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

/// Arranges the contributed toolbar items using the style's item
/// layout. Each item is rendered as a Button whose label is the item
/// title; when an icon is present, the title is prefixed by the icon
/// with a single-cell gap.
private struct ToolbarItemsStrip<S: ToolbarStyle>: View, ResolvableView {
  let items: [ToolbarItemConfig]
  let style: S

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let layout = style.itemLayout
    let content = layout {
      ForEach(items.indices, id: \.self) { index in
        ToolbarItemButton(config: items[index])
      }
    }
    return [content.resolve(in: context)]
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
    .disabled(!config.isEnabled)
  }
}

// Forward the inner scope's identity so chained modifiers keep
// compiling: after the toolbar modifier, the wrapped view is still an
// ActionScope whose id equals the content's.
extension ToolbarHost: Identifiable where Content: ActionScope {
  public typealias ID = Content.ID
  nonisolated public var id: Content.ID { content.id }
}

extension ToolbarHost: ActionScope where Content: ActionScope {}
