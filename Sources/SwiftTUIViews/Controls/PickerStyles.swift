public import SwiftTUICore

/// Defines keyboard behavior and rendered body for a picker.
public protocol PickerStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int?

  /// Enables the primitive's menu expansion actions. Compose the trigger with
  /// `configuration.trigger` and show options while `isActiveNavigation` is true.
  @MainActor
  var wantsTriggerPointerRoute: Bool { get }

  @ViewBuilder @MainActor
  func makeBody(
    configuration: PickerStyleConfiguration
  ) -> Body

  /// Value-type conformance guard; never implement it. The unconstrained
  /// extension below witnesses it for every struct and enum, and the
  /// `Self: AnyObject` overload is unavailable, so a class conformance fails
  /// to compile (plan 2026-08-29-001).
  @_documentation(visibility: internal)
  static var _pickerStyleValueTypeWitness: Void { get }
}

extension PickerStyle {
  @_documentation(visibility: internal)
  public static var _pickerStyleValueTypeWitness: Void { () }
}

extension PickerStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message:
      "SwiftTUI picker styles must be value types (a struct or an enum); a class cannot conform to PickerStyle"
  )
  public static var _pickerStyleValueTypeWitness: Void { () }
}

extension PickerStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }

  @MainActor
  public func selectionDelta(
    for _: KeyEvent
  ) -> Int? {
    nil
  }

  @MainActor
  public var wantsTriggerPointerRoute: Bool {
    false
  }
}

public struct PickerStyleConfiguration: Sendable {
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    /// Captures `content` as the authored label of a fixture-constructed
    /// configuration (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View {
      CapturedSubviewView(payload: payload)
    }
  }

  public struct Option: Sendable {
    /// The option's position in the picker, independent of its display label.
    public var index: Int
    public var label: String
    /// Whether this occurrence matches the current selection binding.
    public var isSelected: Bool
    /// Whether the picker currently accepts input.
    public var isEnabled: Bool
    private var routeIdentity: Identity?

    public init(
      label: String
    ) {
      index = 0
      self.label = label
      isSelected = false
      isEnabled = true
      routeIdentity = nil
    }

    /// Creates an option fixture whose route renders content without a hit target.
    @_spi(StyleFixtures)
    public init(index: Int, label: String, isSelected: Bool, isEnabled: Bool) {
      self.index = index
      self.label = label
      self.isSelected = isSelected
      self.isEnabled = isEnabled
      routeIdentity = nil
    }

    /// Routes a click on `content` to this option's selection. Install once
    /// per option; duplicates report `style.duplicateRoute` and the first wins.
    @ViewBuilder @MainActor
    public func route<Content: View>(
      @ViewBuilder content: () -> Content
    ) -> some View {
      if let routeIdentity {
        StyleRouteView(
          target: .init(identity: routeIdentity, family: "PickerStyle", role: "option"),
          content: content()
        )
      } else {
        content()
      }
    }

    mutating func bindRoute(to identity: Identity) {
      routeIdentity = identity
    }
  }

  public var controlIdentity: Identity
  public var label: Label
  public var options: [Option]
  public var selectedIndex: Int?
  public var isFocused: Bool
  public var isActiveNavigation: Bool
  public var showsFocusEffect: Bool
  public var isEnabled: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var viewportLineCount: Int?
  public var lineWidth: Int?
  private var triggerIdentity: Identity?

  /// Creates a fixture with inert option and trigger routes. `controlIdentity`
  /// is retained for source compatibility; it does not activate fixture routes.
  @_spi(StyleFixtures)
  public init(
    controlIdentity: Identity = Identity(components: ["PickerStyleFixture"]),
    label: Label,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) {
    self.controlIdentity = controlIdentity
    self.label = label
    self.options = options.enumerated().map { index, option in
      Option(
        index: index,
        label: option.label,
        isSelected: index == selectedIndex,
        isEnabled: isEnabled
      )
    }
    self.selectedIndex = selectedIndex
    self.isFocused = isFocused
    self.isActiveNavigation = isActiveNavigation
    self.showsFocusEffect = showsFocusEffect
    self.isEnabled = isEnabled
    self.styleEnvironment = styleEnvironment
    self.viewportLineCount = viewportLineCount
    self.lineWidth = lineWidth
    triggerIdentity = nil
  }

  /// Routes a click on `content` to menu expansion. Menu styles opt in with
  /// `wantsTriggerPointerRoute`; keyboard interaction survives omission of
  /// this wrapper. Fixture configurations never install a pointer target.
  @ViewBuilder @MainActor
  public func trigger<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let triggerIdentity {
      StyleRouteView(
        target: .init(identity: triggerIdentity, family: "PickerStyle", role: "trigger"),
        content: content()
      )
    } else {
      content()
    }
  }

  mutating func bindRoutes(to identity: Identity) {
    triggerIdentity = pickerTriggerIdentity(for: identity)
    for index in options.indices {
      options[index].bindRoute(to: pickerOptionIdentity(for: identity, index: index))
    }
  }
}

/// Type-erased storage for a concrete picker style.
public struct AnyPickerStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyPickerStyleBox

  public init<S: PickerStyle>(
    _ style: S
  ) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyPickerStyleBox(style: style)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  public static var automatic: Self {
    Self(AutomaticPickerStyle())
  }

  public static var inline: Self {
    Self(InlinePickerStyle())
  }

  public static var segmented: Self {
    Self(SegmentedPickerStyle())
  }

  public static var radioGroup: Self {
    Self(RadioGroupPickerStyle())
  }

  public static var menu: Self {
    Self(MenuPickerStyle())
  }

  @MainActor
  package func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    box.selectionDelta(for: event)
  }

  @MainActor
  package var wantsTriggerPointerRoute: Bool {
    box.wantsTriggerPointerRoute
  }

  @MainActor
  package func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

extension AnyPickerStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The environment-driven default picker style.
public struct AutomaticPickerStyle: Sendable, PickerStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyPickerStyle.automatic"
  }

  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    InlinePickerStyleBody(configuration: configuration)
  }
}

/// A vertically arranged picker style that keeps options inline.
public struct InlinePickerStyle: Sendable, PickerStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyPickerStyle.inline"
  }

  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    InlinePickerStyleBody(configuration: configuration)
  }
}

/// A compact horizontal picker style for mutually exclusive options.
public struct SegmentedPickerStyle: Sendable, PickerStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyPickerStyle.segmented"
  }

  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowLeft:
      -1
    case .arrowRight:
      1
    default:
      nil
    }
  }

  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    SegmentedPickerStyleBody(configuration: configuration)
  }
}

/// A vertical radio-button picker style.
public struct RadioGroupPickerStyle: Sendable, PickerStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyPickerStyle.radioGroup"
  }

  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    RadioGroupPickerStyleBody(configuration: configuration)
  }
}

/// A collapsed picker style that opens a menu-like option list.
public struct MenuPickerStyle: Sendable, PickerStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyPickerStyle.menu"
  }

  @MainActor
  public func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    switch event {
    case .arrowUp:
      -1
    case .arrowDown:
      1
    default:
      nil
    }
  }

  @MainActor
  public var wantsTriggerPointerRoute: Bool {
    true
  }

  @MainActor
  public func makeBody(
    configuration: PickerStyleConfiguration
  ) -> some View {
    MenuPickerStyleBody(configuration: configuration)
  }
}

private protocol AnyPickerStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyPickerStyleBox) -> Bool

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int?

  @MainActor
  var wantsTriggerPointerRoute: Bool { get }

  @MainActor
  func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyPickerStyleBox<S: PickerStyle>: AnyPickerStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyPickerStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int? {
    style.selectionDelta(for: event)
  }

  @MainActor
  var wantsTriggerPointerRoute: Bool {
    style.wantsTriggerPointerRoute
  }

  @MainActor
  func resolveBody(
    configuration: PickerStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

// The builtin picker styles: stateless, so type identity settles reuse.
extension AutomaticPickerStyle: ReuseTransparentStyle {}
extension InlinePickerStyle: ReuseTransparentStyle {}
extension SegmentedPickerStyle: ReuseTransparentStyle {}
extension RadioGroupPickerStyle: ReuseTransparentStyle {}
extension MenuPickerStyle: ReuseTransparentStyle {}
