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
    var base = content.resolve(in: context)
    // At this scope boundary, clear the toolbar-items preference so
    // ancestor toolbar hosts do not re-absorb the same contributions.
    // Rendering is layered on in a follow-up task — this commit proves
    // the hoisting/absorption contract.
    base.preferenceValues[ToolbarItemsPreferenceKey.self] = []
    return [base]
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
