/// Horizontal and vertical spacing preferences for a view.
public struct Spacing: Equatable, Sendable {
  public var horizontal: Int?
  public var vertical: Int?

  public init(horizontal: Int? = nil, vertical: Int? = nil) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  public func merging(_ other: Self) -> Self {
    Self(
      horizontal: other.horizontal ?? horizontal,
      vertical: other.vertical ?? vertical
    )
  }
}

/// An edge of a rectangle.
public enum Edge: Int8, CaseIterable, Sendable {
  case top, leading, bottom, trailing

  /// An option set of edges.
  public struct Set: OptionSet, Sendable {
    public let rawValue: Int8

    public init(rawValue: Int8) {
      self.rawValue = rawValue
    }

    public static let top = Set(rawValue: 1 << 0)
    public static let leading = Set(rawValue: 1 << 1)
    public static let bottom = Set(rawValue: 1 << 2)
    public static let trailing = Set(rawValue: 1 << 3)

    public static let horizontal: Set = [.leading, .trailing]
    public static let vertical: Set = [.top, .bottom]
    public static let all: Set = [.top, .leading, .bottom, .trailing]

    public init(_ edge: Edge) {
      switch edge {
      case .top: self = .top
      case .leading: self = .leading
      case .bottom: self = .bottom
      case .trailing: self = .trailing
      }
    }
  }
}

/// Edge insets expressed in terminal cells.
public struct EdgeInsets: Equatable, Sendable {
  public var top: Int
  public var leading: Int
  public var bottom: Int
  public var trailing: Int

  public init(
    top: Int = 0,
    leading: Int = 0,
    bottom: Int = 0,
    trailing: Int = 0
  ) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public init(all value: Int) {
    self.init(top: value, leading: value, bottom: value, trailing: value)
  }

  public init(horizontal: Int = 0, vertical: Int = 0) {
    self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
  }

  public var horizontal: Int {
    leading + trailing
  }

  public var vertical: Int {
    top + bottom
  }

  public static let zero = Self()

  public var isZero: Bool {
    top == 0 && leading == 0 && bottom == 0 && trailing == 0
  }

  public func value(for edge: Edge) -> Int {
    switch edge {
    case .top:
      top
    case .leading:
      leading
    case .bottom:
      bottom
    case .trailing:
      trailing
    }
  }

  public func masked(to edges: Edge.Set) -> Self {
    Self(
      top: edges.contains(.top) ? top : 0,
      leading: edges.contains(.leading) ? leading : 0,
      bottom: edges.contains(.bottom) ? bottom : 0,
      trailing: edges.contains(.trailing) ? trailing : 0
    )
  }

  public func zeroing(_ edges: Edge.Set) -> Self {
    Self(
      top: edges.contains(.top) ? 0 : top,
      leading: edges.contains(.leading) ? 0 : leading,
      bottom: edges.contains(.bottom) ? 0 : bottom,
      trailing: edges.contains(.trailing) ? 0 : trailing
    )
  }

  public func adding(_ other: Self) -> Self {
    Self(
      top: top + other.top,
      leading: leading + other.leading,
      bottom: bottom + other.bottom,
      trailing: trailing + other.trailing
    )
  }

  public func adding(
    _ amount: Int,
    to edges: Edge.Set
  ) -> Self {
    Self(
      top: top + (edges.contains(.top) ? amount : 0),
      leading: leading + (edges.contains(.leading) ? amount : 0),
      bottom: bottom + (edges.contains(.bottom) ? amount : 0),
      trailing: trailing + (edges.contains(.trailing) ? amount : 0)
    )
  }
}

/// A normalized point in a shape's bounds where `(0, 0)` is the
/// top-leading corner and `(1, 1)` is the bottom-trailing corner.
///
/// Used by gradient start/end points where interpolation requires
/// continuous unit coordinates — ``Alignment`` identifies named
/// layout slots via `AlignmentID`-keyed guides, while ``UnitPoint``
/// is a concrete `(x, y)` pair that can be interpolated element-wise
/// by the animation pipeline.  The named static constants
/// (``topLeading``, ``center``, etc.) mirror ``Alignment``'s named
/// constants so most gradient call sites compile unchanged.
public struct UnitPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public static let zero = UnitPoint(x: 0, y: 0)

  public static let topLeading = UnitPoint(x: 0, y: 0)
  public static let top = UnitPoint(x: 0.5, y: 0)
  public static let topTrailing = UnitPoint(x: 1, y: 0)

  public static let leading = UnitPoint(x: 0, y: 0.5)
  public static let center = UnitPoint(x: 0.5, y: 0.5)
  public static let trailing = UnitPoint(x: 1, y: 0.5)

  public static let bottomLeading = UnitPoint(x: 0, y: 1)
  public static let bottom = UnitPoint(x: 0.5, y: 1)
  public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

extension UnitPoint: Animatable {
  public var animatableData: AnimatablePair<Double, Double> {
    get { .init(x, y) }
    set {
      x = newValue.first
      y = newValue.second
    }
  }
}

/// A size expressed in unit coordinates.
public struct UnitSize: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double

  public init(
    width: Double,
    height: Double
  ) {
    self.width = width
    self.height = height
  }

  public static let zero = UnitSize(width: 0, height: 0)
}

/// A rectangle expressed relative to another rectangle's bounds.
public struct UnitRect: Equatable, Hashable, Sendable {
  public var origin: UnitPoint
  public var size: UnitSize

  public init(
    origin: UnitPoint,
    size: UnitSize
  ) {
    self.origin = origin
    self.size = size
  }

  /// The complete bounds of the source rectangle.
  public static let bounds = UnitRect(
    origin: .zero,
    size: UnitSize(width: 1, height: 1)
  )
}

extension EdgeInsets: Animatable {
  public typealias AnimatableData = AnimatablePair<
    AnimatablePair<Int, Int>,
    AnimatablePair<Int, Int>
  >

  public var animatableData: AnimatableData {
    get {
      AnimatablePair(
        AnimatablePair(top, leading),
        AnimatablePair(bottom, trailing)
      )
    }
    set {
      top = newValue.first.first
      leading = newValue.first.second
      bottom = newValue.second.first
      trailing = newValue.second.second
    }
  }
}

/// A combined horizontal and vertical alignment.
public struct Alignment: Equatable, Hashable, Sendable {
  public let horizontal: HorizontalAlignment
  public let vertical: VerticalAlignment

  public init(
    horizontal: HorizontalAlignment,
    vertical: VerticalAlignment
  ) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  public var debugName: String {
    switch (horizontal, vertical) {
    case (.leading, .top):
      return "topLeading"
    case (.center, .top):
      return "top"
    case (.trailing, .top):
      return "topTrailing"
    case (.leading, .center):
      return "leading"
    case (.center, .center):
      return "center"
    case (.trailing, .center):
      return "trailing"
    case (.leading, .bottom):
      return "bottomLeading"
    case (.center, .bottom):
      return "bottom"
    case (.trailing, .bottom):
      return "bottomTrailing"
    default:
      return "\(horizontal.debugName)-\(vertical.debugName)"
    }
  }

  public var rawValue: String {
    debugName
  }
}

/// Protocol used to define custom alignment guides.
public protocol AlignmentID: Sendable {
  static func defaultValue(in context: ViewDimensions) -> Int
}

/// A horizontal alignment guide.
public struct HorizontalAlignment: Sendable {
  package let key: ObjectIdentifier
  public let debugName: String
  private let defaultValueProvider: @Sendable (ViewDimensions) -> Int

  public init(_ id: any AlignmentID.Type) {
    key = ObjectIdentifier(id)
    debugName = String(reflecting: id)
    defaultValueProvider = { context in
      id.defaultValue(in: context)
    }
  }

  fileprivate init(
    key: ObjectIdentifier,
    debugName: String,
    defaultValueProvider: @escaping @Sendable (ViewDimensions) -> Int
  ) {
    self.key = key
    self.debugName = debugName
    self.defaultValueProvider = defaultValueProvider
  }

  fileprivate func defaultValue(in context: ViewDimensions) -> Int {
    defaultValueProvider(context)
  }
}

extension HorizontalAlignment: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.key == rhs.key
  }
}

extension HorizontalAlignment: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
  }
}

/// A vertical alignment guide.
public struct VerticalAlignment: Sendable {
  package let key: ObjectIdentifier
  public let debugName: String
  private let defaultValueProvider: @Sendable (ViewDimensions) -> Int

  public init(_ id: any AlignmentID.Type) {
    key = ObjectIdentifier(id)
    debugName = String(reflecting: id)
    defaultValueProvider = { context in
      id.defaultValue(in: context)
    }
  }

  fileprivate init(
    key: ObjectIdentifier,
    debugName: String,
    defaultValueProvider: @escaping @Sendable (ViewDimensions) -> Int
  ) {
    self.key = key
    self.debugName = debugName
    self.defaultValueProvider = defaultValueProvider
  }

  fileprivate func defaultValue(in context: ViewDimensions) -> Int {
    defaultValueProvider(context)
  }
}

extension VerticalAlignment: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.key == rhs.key
  }
}

extension VerticalAlignment: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(key)
  }
}

/// Size and alignment guide values exposed during layout.
public struct ViewDimensions: Sendable {
  public let width: Int
  public let height: Int
  private let explicitHorizontalGuideProvider: @Sendable (HorizontalAlignment) -> Int?
  private let explicitVerticalGuideProvider: @Sendable (VerticalAlignment) -> Int?

  public init(width: Int, height: Int) {
    self.init(
      width: width,
      height: height,
      explicitHorizontalGuideProvider: { _ in nil },
      explicitVerticalGuideProvider: { _ in nil }
    )
  }

  public subscript(guide: HorizontalAlignment) -> Int {
    explicitHorizontalGuideProvider(guide) ?? guide.defaultValue(in: self)
  }

  public subscript(guide: VerticalAlignment) -> Int {
    explicitVerticalGuideProvider(guide) ?? guide.defaultValue(in: self)
  }

  package func explicitValue(for guide: HorizontalAlignment) -> Int? {
    explicitHorizontalGuideProvider(guide)
  }

  package func explicitValue(for guide: VerticalAlignment) -> Int? {
    explicitVerticalGuideProvider(guide)
  }

  package func overridingHorizontalGuides(
    with provider: @escaping @Sendable (HorizontalAlignment) -> Int?
  ) -> Self {
    let currentHorizontalProvider = explicitHorizontalGuideProvider
    return Self(
      width: width,
      height: height,
      explicitHorizontalGuideProvider: { alignment in
        provider(alignment) ?? currentHorizontalProvider(alignment)
      },
      explicitVerticalGuideProvider: explicitVerticalGuideProvider
    )
  }

  package func overridingVerticalGuides(
    with provider: @escaping @Sendable (VerticalAlignment) -> Int?
  ) -> Self {
    let currentVerticalProvider = explicitVerticalGuideProvider
    return Self(
      width: width,
      height: height,
      explicitHorizontalGuideProvider: explicitHorizontalGuideProvider,
      explicitVerticalGuideProvider: { alignment in
        provider(alignment) ?? currentVerticalProvider(alignment)
      }
    )
  }

  fileprivate init(
    width: Int,
    height: Int,
    explicitHorizontalGuideProvider: @escaping @Sendable (HorizontalAlignment) -> Int?,
    explicitVerticalGuideProvider: @escaping @Sendable (VerticalAlignment) -> Int?
  ) {
    self.width = width
    self.height = height
    self.explicitHorizontalGuideProvider = explicitHorizontalGuideProvider
    self.explicitVerticalGuideProvider = explicitVerticalGuideProvider
  }
}

private enum LeadingAlignmentID: AlignmentID {
  static func defaultValue(in _: ViewDimensions) -> Int { 0 }
}

private enum HorizontalCenterAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.width / 2 }
}

private enum TrailingAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.width }
}

private enum TopAlignmentID: AlignmentID {
  static func defaultValue(in _: ViewDimensions) -> Int { 0 }
}

private enum VerticalCenterAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.height / 2 }
}

private enum BottomAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.height }
}

private enum FirstTextBaselineAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.height }
}

private enum LastTextBaselineAlignmentID: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> Int { context.height }
}

extension HorizontalAlignment {
  public static let leading = Self(
    key: ObjectIdentifier(LeadingAlignmentID.self),
    debugName: "leading",
    defaultValueProvider: { _ in 0 }
  )
  public static let center = Self(
    key: ObjectIdentifier(HorizontalCenterAlignmentID.self),
    debugName: "center",
    defaultValueProvider: { context in context.width / 2 }
  )
  public static let trailing = Self(
    key: ObjectIdentifier(TrailingAlignmentID.self),
    debugName: "trailing",
    defaultValueProvider: { context in context.width }
  )
}

extension VerticalAlignment {
  public static let top = Self(
    key: ObjectIdentifier(TopAlignmentID.self),
    debugName: "top",
    defaultValueProvider: { _ in 0 }
  )
  public static let center = Self(
    key: ObjectIdentifier(VerticalCenterAlignmentID.self),
    debugName: "center",
    defaultValueProvider: { context in context.height / 2 }
  )
  public static let bottom = Self(
    key: ObjectIdentifier(BottomAlignmentID.self),
    debugName: "bottom",
    defaultValueProvider: { context in context.height }
  )
  public static let firstTextBaseline = Self(
    key: ObjectIdentifier(FirstTextBaselineAlignmentID.self),
    debugName: "firstTextBaseline",
    defaultValueProvider: { context in context.height }
  )
  public static let lastTextBaseline = Self(
    key: ObjectIdentifier(LastTextBaselineAlignmentID.self),
    debugName: "lastTextBaseline",
    defaultValueProvider: { context in context.height }
  )
}

extension Alignment {
  public static let topLeading = Self(horizontal: .leading, vertical: .top)
  public static let top = Self(horizontal: .center, vertical: .top)
  public static let topTrailing = Self(horizontal: .trailing, vertical: .top)
  public static let leading = Self(horizontal: .leading, vertical: .center)
  public static let center = Self(horizontal: .center, vertical: .center)
  public static let trailing = Self(horizontal: .trailing, vertical: .center)
  public static let bottomLeading = Self(horizontal: .leading, vertical: .bottom)
  public static let bottom = Self(horizontal: .center, vertical: .bottom)
  public static let bottomTrailing = Self(horizontal: .trailing, vertical: .bottom)
  public static let leadingLastTextBaseline = Self(
    horizontal: .leading,
    vertical: .lastTextBaseline
  )
  public static let trailingFirstTextBaseline = Self(
    horizontal: .trailing,
    vertical: .firstTextBaseline
  )
}

/// The high-level phases of the rendering pipeline.
public enum Phase: String, CaseIterable, Sendable {
  case resolve
  case measure
  case place
  case semantics
  case draw
  case raster
  case commit
}

/// A stable identity path used to key state and runtime bookkeeping.
public struct IdentityComponent: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String

  package init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static func named(
    _ name: StaticString
  ) -> Self {
    .init(rawValue: String(describing: name))
  }

  public static func indexed(
    _ kind: StaticString,
    index: Int
  ) -> Self {
    .init(rawValue: "\(String(describing: kind))[\(index)]")
  }

  public var description: String {
    rawValue
  }
}

public struct Identity: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
  public let components: [String]

  public init(components: [String]) {
    self.components = components
  }

  public init(components: [IdentityComponent]) {
    self.components = components.map(\.rawValue)
  }

  public var path: String {
    components.joined(separator: "/")
  }

  public var description: String {
    path
  }

  public var parent: Self? {
    guard !components.isEmpty else {
      return nil
    }
    return Self(components: Array(components.dropLast()))
  }

  public func child(_ component: String) -> Self {
    Self(components: components + [component])
  }

  public func child(
    _ component: IdentityComponent
  ) -> Self {
    Self(components: components + [component.rawValue])
  }

  public var lastComponent: String? {
    components.last
  }

  public func explicitID<ID: Hashable>(_ id: ID) -> Self {
    child("ID[\(escapedExplicitIDComponent(String(reflecting: id)))]")
  }

  public func isAncestor(of other: Self) -> Bool {
    guard components.count <= other.components.count else {
      return false
    }

    return zip(components, other.components).allSatisfy(==)
  }

  public func isDescendant(of other: Self) -> Bool {
    other.isAncestor(of: self)
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.path < rhs.path
  }

  private func escapedExplicitIDComponent(_ component: String) -> String {
    let escaped = component.reduce(into: "") { escaped, character in
      switch character {
      case "%":
        escaped.append("%25")
      case "/":
        escaped.append("%2F")
      default:
        escaped.append(character)
      }
    }
    return escaped.isEmpty ? "<empty>" : escaped
  }
}

package struct StructuralPath: Hashable, Sendable, Codable, CustomStringConvertible {
  package let components: [IdentityComponent]

  package init(components: [IdentityComponent] = []) {
    self.components = components
  }

  package init(identity: Identity) {
    components = identity.components.map { IdentityComponent(rawValue: $0) }
  }

  package var identityProjection: Identity {
    Identity(components: components)
  }

  package var parent: Self? {
    guard !components.isEmpty else {
      return nil
    }
    return Self(components: Array(components.dropLast()))
  }

  package func appending(_ component: IdentityComponent) -> Self {
    Self(components: components + [component])
  }

  package func isAncestor(of other: Self) -> Bool {
    guard components.count <= other.components.count else {
      return false
    }
    return zip(components, other.components).allSatisfy(==)
  }

  package var description: String {
    components.map(\.rawValue).joined(separator: "/")
  }
}

package struct EntityIdentity: Hashable, Sendable, CustomStringConvertible {
  package var value: AnyID
  package var occurrence: Int
  package var debugDescription: String

  package init<ID: Hashable & Sendable>(
    _ value: ID,
    occurrence: Int = 0
  ) {
    self.value = AnyID(value)
    self.occurrence = occurrence
    debugDescription = String(reflecting: value)
  }

  package init<ID: Hashable & Sendable>(
    forEachValue value: ID,
    occurrence: Int = 0,
    scope: StructuralPath
  ) {
    self.value = AnyID(ScopedForEachEntityID(scope: scope, value: value))
    self.occurrence = occurrence
    debugDescription = String(reflecting: value)
  }

  private init(
    value: AnyID,
    occurrence: Int,
    debugDescription: String
  ) {
    self.value = value
    self.occurrence = occurrence
    self.debugDescription = debugDescription
  }

  package func withOccurrence(_ occurrence: Int) -> Self {
    Self(
      value: value,
      occurrence: occurrence,
      debugDescription: debugDescription
    )
  }

  package var description: String {
    occurrence == 0
      ? debugDescription
      : "\(debugDescription)#\(occurrence)"
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value == rhs.value
      && lhs.occurrence == rhs.occurrence
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(value)
    hasher.combine(occurrence)
  }
}

private struct ScopedForEachEntityID<Value: Hashable & Sendable>: Hashable, Sendable {
  var scope: StructuralPath
  var value: Value
}

/// A single proposed dimension used during measure.
public enum ProposedDimension: Equatable, Hashable, Sendable {
  case unspecified
  case finite(Int)
  case infinity
}

extension ProposedDimension: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .finite(value)
  }
}

/// A width and height proposal passed from parent to child during layout.
public struct ProposedSize: Equatable, Hashable, Sendable {
  public var width: ProposedDimension
  public var height: ProposedDimension

  public init(
    width: ProposedDimension = .unspecified,
    height: ProposedDimension = .unspecified
  ) {
    self.width = width
    self.height = height
  }

  public init(width: Int?, height: Int?) {
    self.width = width.map(ProposedDimension.finite) ?? .unspecified
    self.height = height.map(ProposedDimension.finite) ?? .unspecified
  }

  public static let unspecified = Self()
}
