import SwiftTUICore

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
/// toolbar items. The host composes the strip above or below its
/// content per `placement`.
///
/// A toolbar host reads the nearest `toolbarStyle(_:)` value from the
/// environment; the style is not passed at the declaration.
public protocol ToolbarStyle: Sendable {
  associatedtype ItemLayout: Layout
  var itemLayout: ItemLayout { get }
  var placement: ToolbarPlacement { get }
  var snapshotLabel: String { get }
}

extension ToolbarStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// A top-placed toolbar that lays items out horizontally with a
/// single-cell gap.
public struct DefaultTopToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .top }

  public var snapshotLabel: String { "ToolbarStyle.defaultTop" }

  public init() {}
}

/// A bottom-placed toolbar that lays items out horizontally with a
/// single-cell gap.
public struct DefaultBottomToolbarStyle: ToolbarStyle {
  public var itemLayout: HStackLayout {
    HStackLayout(alignment: .center, spacing: 1)
  }
  public var placement: ToolbarPlacement { .bottom }

  public var snapshotLabel: String { "ToolbarStyle.defaultBottom" }

  public init() {}
}

extension ToolbarStyle where Self == DefaultTopToolbarStyle {
  public static var defaultTop: DefaultTopToolbarStyle { .init() }
}

extension ToolbarStyle where Self == DefaultBottomToolbarStyle {
  public static var defaultBottom: DefaultBottomToolbarStyle { .init() }
}

extension DefaultTopToolbarStyle: ReuseTransparentStyle {}
extension DefaultBottomToolbarStyle: ReuseTransparentStyle {}

private protocol AnyToolbarStyleBox: Sendable {
  var snapshotLabel: String { get }
  var placement: ToolbarPlacement { get }
  /// The *concrete* item layout's reuse signature.
  ///
  /// Load-bearing: the toolbar strip's reuse-cache key is derived from the
  /// concrete layout's type and signature. Deriving it from the erased
  /// `AnyLayout` instead would give every style the same string and
  /// silently collapse distinct styles onto one cache entry, so the
  /// signature is taken here — where the concrete type is still in hand —
  /// rather than recomputed downstream.
  var layoutSignature: String? { get }

  @MainActor
  func itemLayout() -> AnyLayout
  func isEqualForReuse(to other: any AnyToolbarStyleBox) -> Bool
}

private struct ConcreteToolbarStyleBox<S: ToolbarStyle>: AnyToolbarStyleBox {
  let style: S

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var placement: ToolbarPlacement {
    style.placement
  }

  var layoutSignature: String? {
    toolbarLayoutSignature(style.itemLayout)
  }

  @MainActor
  func itemLayout() -> AnyLayout {
    AnyLayout(style.itemLayout)
  }

  func isEqualForReuse(to other: any AnyToolbarStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased toolbar style.
///
/// The concrete style stays boxed rather than being flattened at
/// construction: the box keeps the concrete item layout available for the
/// strip's reuse signature, and it keeps this initializer free of actor
/// isolation (`AnyLayout`'s is `@MainActor`) so the environment key can
/// hold a `static let` default.
public struct AnyToolbarStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyToolbarStyleBox

  public init<S: ToolbarStyle>(
    _ style: S
  ) {
    box = ConcreteToolbarStyleBox(style: style)
  }

  public static var defaultTop: Self {
    Self(DefaultTopToolbarStyle())
  }

  public static var defaultBottom: Self {
    Self(DefaultBottomToolbarStyle())
  }

  public var description: String {
    box.snapshotLabel
  }

  public var debugDescription: String {
    description
  }

  package var snapshotLabel: String {
    box.snapshotLabel
  }

  package var placement: ToolbarPlacement {
    box.placement
  }

  package var layoutSignature: String? {
    box.layoutSignature
  }

  @MainActor
  package var itemLayout: AnyLayout {
    box.itemLayout()
  }
}

extension AnyToolbarStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}
