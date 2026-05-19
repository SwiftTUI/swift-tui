public import SwiftTUICore

private protocol AnyOutlineStyleBox: Sendable {
  var baseValue: Any { get }
  var description: String { get }
  var debugDescription: String { get }

  func makePresentation() -> OutlineStylePresentation
  func isEqual(to other: any AnyOutlineStyleBox) -> Bool
  func hash(into hasher: inout Hasher)
}

private struct ConcreteOutlineStyleBox<S: OutlineStyle>: AnyOutlineStyleBox {
  let style: S

  var baseValue: Any {
    style
  }

  var description: String {
    String(describing: style)
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  func makePresentation() -> OutlineStylePresentation {
    var presentation = style.makeOutlineStylePresentation()
    presentation.snapshotLabel = description
    return presentation
  }

  func isEqual(to other: any AnyOutlineStyleBox) -> Bool {
    guard let otherStyle = other.baseValue as? S else {
      return false
    }
    return otherStyle == style
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(style)
  }
}

/// An extensible outline style for hierarchical connectors and indent guides.
public protocol OutlineStyle: Hashable, Sendable {
  func makeOutlineStylePresentation() -> OutlineStylePresentation
}

/// A type-erased outline style.
public struct AnyOutlineStyle:
  Hashable,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  private let box: any AnyOutlineStyleBox

  public init<S: OutlineStyle>(
    _ style: S
  ) {
    box = ConcreteOutlineStyleBox(style: style)
  }

  public static var automatic: Self {
    Self(AutomaticOutlineStyle())
  }

  public static var rounded: Self {
    Self(RoundedOutlineStyle())
  }

  public static var plain: Self {
    Self(PlainOutlineStyle())
  }

  public static var ascii: Self {
    Self(ASCIIOutlineStyle())
  }

  public var description: String {
    box.description
  }

  public var debugDescription: String {
    box.debugDescription
  }

  package var presentation: OutlineStylePresentation {
    box.makePresentation()
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }

  public func hash(into hasher: inout Hasher) {
    box.hash(into: &hasher)
  }
}

/// The default outline style that resolves to rounded connectors.
public struct AutomaticOutlineStyle:
  OutlineStyle,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public init() {}

  public func makeOutlineStylePresentation() -> OutlineStylePresentation {
    .rounded
  }

  public var description: String {
    "OutlineStyle.automatic"
  }

  public var debugDescription: String {
    description
  }
}

/// An outline style with rounded leaf connectors.
public struct RoundedOutlineStyle:
  OutlineStyle,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public init() {}

  public func makeOutlineStylePresentation() -> OutlineStylePresentation {
    .rounded
  }

  public var description: String {
    "OutlineStyle.rounded"
  }

  public var debugDescription: String {
    description
  }
}

/// An outline style that uses box-drawing connectors throughout.
public struct PlainOutlineStyle:
  OutlineStyle,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public init() {}

  public func makeOutlineStylePresentation() -> OutlineStylePresentation {
    .plain
  }

  public var description: String {
    "OutlineStyle.plain"
  }

  public var debugDescription: String {
    description
  }
}

/// An outline style that uses ASCII-only connectors.
public struct ASCIIOutlineStyle:
  OutlineStyle,
  Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  public init() {}

  public func makeOutlineStylePresentation() -> OutlineStylePresentation {
    .ascii
  }

  public var description: String {
    "OutlineStyle.ascii"
  }

  public var debugDescription: String {
    description
  }
}
