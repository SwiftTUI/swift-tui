public import SwiftTUICore

// The toolbar style vocabulary.
//
// `ToolbarStyle` is the extensible style protocol an `ActionScope` toolbar is
// configured with: it supplies the `Layout` that arranges toolbar items and
// the `ToolbarPlacement` (top or bottom) the host composes against. The two
// `Default*ToolbarStyle` values are the built-in conformances, surfaced
// through the `defaultTop` / `defaultBottom` static accessors.
//
// Split out of `Toolbar.swift` so that file stays focused on the toolbar
// modifier, preference reconciliation, and the resolved-node scope machinery.
//
// `check_public_surface_policies.sh` pins `public protocol ToolbarStyle` by
// file path; that guardrail path was updated to this file in the same change.

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
