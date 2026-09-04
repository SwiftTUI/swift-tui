public import SwiftTUICore

/// An extensible table style.
///
/// A table style resolves a `TableStylePresentation` — border glyphs,
/// header paints, insets, and border paint — from the table's render state.
/// The table primitive keeps virtualization, selection, header semantics,
/// cell layout, pointer routes, and scroll currency; a style cannot change
/// them.
public protocol TableStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation
}

extension TableStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a table style may consult.
public struct TableStyleConfiguration: Sendable {
  public var columnCount: Int
  public var showsHeaders: Bool
  public var isSelectable: Bool
  public var isEnabled: Bool
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    columnCount: Int,
    showsHeaders: Bool,
    isSelectable: Bool,
    isEnabled: Bool,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.columnCount = columnCount
    self.showsHeaders = showsHeaders
    self.isSelectable = isSelectable
    self.isEnabled = isEnabled
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
  }
}

private protocol AnyTableStyleBox: Sendable {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation
  func isEqualForReuse(to other: any AnyTableStyleBox) -> Bool
}

private struct ConcreteTableStyleBox<S: TableStyle>: AnyTableStyleBox {
  let style: S

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    var presentation = style.resolvePresentation(for: configuration)
    presentation.snapshotLabel = style.snapshotLabel
    return presentation
  }

  func isEqualForReuse(to other: any AnyTableStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased table style.
public struct AnyTableStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnyTableStyleBox

  public init<S: TableStyle>(
    _ style: S
  ) {
    box = ConcreteTableStyleBox(style: style)
  }

  public static var automatic: Self {
    Self(AutomaticTableStyle())
  }

  public static var inset: Self {
    Self(InsetTableStyle())
  }

  public static var bordered: Self {
    Self(BorderedTableStyle())
  }

  public var description: String {
    box.snapshotLabel
  }

  public var debugDescription: String {
    box.debugDescription
  }

  @MainActor
  package func presentation(for configuration: TableStyleConfiguration) -> TableStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnyTableStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The default table style.
///
/// Adaptive, not a fixed alias: it currently resolves the same rounded inset
/// treatment as ``InsetTableStyle`` — preserving the table result the former
/// automatic list style produced — and may adapt later without a contract
/// break.
public struct AutomaticTableStyle: TableStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "TableStyle.automatic"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .inset
  }
}

/// The rounded inset treatment (the former inset-grouped collection result).
public struct InsetTableStyle: TableStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "TableStyle.inset"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .inset
  }
}

/// The square-bordered treatment (the former plain collection result).
public struct BorderedTableStyle: TableStyle, Sendable {
  public init() {}

  public var snapshotLabel: String {
    "TableStyle.bordered"
  }

  @MainActor
  public func resolvePresentation(
    for configuration: TableStyleConfiguration
  ) -> TableStylePresentation {
    .bordered
  }
}

extension AutomaticTableStyle: ReuseTransparentStyle {}
extension InsetTableStyle: ReuseTransparentStyle {}
extension BorderedTableStyle: ReuseTransparentStyle {}
