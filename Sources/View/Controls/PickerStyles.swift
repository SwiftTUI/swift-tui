public import Core

public protocol PickerStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @MainActor
  func selectionDelta(
    for event: KeyEvent
  ) -> Int?

  @MainActor
  var wantsTriggerPointerRoute: Bool { get }

  @ViewBuilder @MainActor
  func makeBody(
    configuration: PickerStyleConfiguration
  ) -> Body
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
    package let payload: DeferredViewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = DeferredViewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    public var body: some View {
      DeferredPayloadView(payload: payload)
    }
  }

  public struct Option: Sendable {
    public var label: String

    public init(
      label: String
    ) {
      self.label = label
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

  package init(
    controlIdentity: Identity,
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
    self.options = options
    self.selectedIndex = selectedIndex
    self.isFocused = isFocused
    self.isActiveNavigation = isActiveNavigation
    self.showsFocusEffect = showsFocusEffect
    self.isEnabled = isEnabled
    self.styleEnvironment = styleEnvironment
    self.viewportLineCount = viewportLineCount
    self.lineWidth = lineWidth
  }
}

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
    normalizeResolvedElements(
      resolveViewElements(
        style.makeBody(configuration: configuration),
        in: context
      ),
      in: context
    )
  }
}
