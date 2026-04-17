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
