@_spi(Testing) public import SwiftTUICore

/// Type-erased storage for a concrete tab-view style.
public struct AnyTabViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTabViewStyleBox

  public init<S: TabViewStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyTabViewStyleBox(style: style)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  public static var automatic: Self {
    Self(AutomaticTabViewStyle())
  }

  public static var underline: Self {
    Self(UnderlineTabViewStyle())
  }

  public static var literalTabs: Self {
    Self(LiteralTabsTabViewStyle())
  }

  public static var powerline: Self {
    Self(PowerlineTabViewStyle())
  }

  @MainActor
  package func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    box.presentation(for: configuration)
  }

  @MainActor
  package func resolveBody(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    controlIdentity: Identity,
    activeContentIndex: Int?,
    activeContent: DeferredViewPayload?,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      presentation: presentation,
      controlIdentity: controlIdentity,
      activeContentIndex: activeContentIndex,
      activeContent: activeContent,
      in: context
    )
  }
}

/// The environment-driven default tab-view style.
public struct AutomaticTabViewStyle: Sendable {
  public init() {}
}

/// A tab-view style that underlines the selected tab.
public struct UnderlineTabViewStyle: Sendable {
  public init() {}
}

/// A tab-view style that renders labels as literal terminal tabs.
public struct LiteralTabsTabViewStyle: Sendable {
  public init() {}
}

/// A tab-view style that renders connected powerline-style tab segments.
public struct PowerlineTabViewStyle: Sendable {
  public init() {}
}

/// Defines tab strip, overflow, and active tab rendering.
public protocol TabViewStyle: Sendable {
  associatedtype TabBody: View
  associatedtype OverflowTriggerBody: View
  associatedtype OverflowItemBody: View
  associatedtype StripBackgroundBody: View

  var snapshotLabel: String { get }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @ViewBuilder @MainActor
  func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> TabBody

  @ViewBuilder @MainActor
  func makeOverflowTriggerBody(
    configuration: TabViewStyleConfiguration,
    trigger: TabViewOverflowTriggerConfiguration
  ) -> OverflowTriggerBody

  @ViewBuilder @MainActor
  func makeOverflowItemBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration,
    overflow: TabViewOverflowMenuPresentation
  ) -> OverflowItemBody

  @ViewBuilder @MainActor
  func makeStripBackground(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> StripBackgroundBody
}

extension TabViewStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }

  @MainActor
  public func makeOverflowTriggerBody(
    configuration _: TabViewStyleConfiguration,
    trigger _: TabViewOverflowTriggerConfiguration
  ) -> EmptyView {
    EmptyView()
  }

  @MainActor
  public func makeOverflowItemBody(
    configuration _: TabViewStyleConfiguration,
    item _: TabViewStyleItemConfiguration,
    overflow _: TabViewOverflowMenuPresentation
  ) -> EmptyView {
    EmptyView()
  }

  @MainActor
  public func makeStripBackground(
    configuration _: TabViewStyleConfiguration,
    presentation _: TabViewStylePresentation
  ) -> EmptyView {
    EmptyView()
  }
}

public struct TabViewStyleOption: Sendable {
  public var label: TabItemLabel

  public init(
    label: TabItemLabel
  ) {
    self.label = label
  }
}

public struct TabViewStyleItemConfiguration: Sendable {
  public var index: Int
  public var label: TabItemLabel
  public var isSelected: Bool
  public var isFocused: Bool

  public init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
  }
}

public struct TabViewOverflowTriggerConfiguration: Sendable {
  public var label: String
  public var isSelected: Bool
  public var isFocused: Bool
  public var isExpanded: Bool
  public var overflowIndices: [Int]
  public var leadingWidth: Int

  public init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
  }
}

public struct TabViewOverflowMenuPresentation: Sendable {
  public var triggerLeadingWidth: Int
  public var overflowIndices: [Int]
  public var isExpanded: Bool
  public var selectedOverflowIndex: Int?
  public var focusedOverflowIndex: Int?
  public var triggerLabel: String
  public var contentPadding: EdgeInsets
  public var backgroundStyle: AnyShapeStyle?
  public var borderStyle: AnyShapeStyle?
  public var borderInset: Int
  public var cornerRadius: Int

  public var isTriggerSelected: Bool {
    selectedOverflowIndex != nil
  }

  public var isTriggerFocused: Bool {
    focusedOverflowIndex != nil
  }

  public var preferredOverflowFocusIndex: Int? {
    focusedOverflowIndex ?? selectedOverflowIndex ?? overflowIndices.first
  }

  public init(
    triggerLeadingWidth: Int,
    overflowIndices: [Int],
    isExpanded: Bool,
    selectedOverflowIndex: Int?,
    focusedOverflowIndex: Int?,
    triggerLabel: String,
    contentPadding: EdgeInsets = .zero,
    backgroundStyle: AnyShapeStyle? = nil,
    borderStyle: AnyShapeStyle? = nil,
    borderInset: Int = 0,
    cornerRadius: Int = 0
  ) {
    self.triggerLeadingWidth = triggerLeadingWidth
    self.overflowIndices = overflowIndices
    self.isExpanded = isExpanded
    self.selectedOverflowIndex = selectedOverflowIndex
    self.focusedOverflowIndex = focusedOverflowIndex
    self.triggerLabel = triggerLabel
    self.contentPadding = contentPadding
    self.backgroundStyle = backgroundStyle
    self.borderStyle = borderStyle
    self.borderInset = borderInset
    self.cornerRadius = cornerRadius
  }
}

public struct TabViewStylePresentation: Sendable {
  public var stripHeight: Int
  public var visibleOptionIndices: [Int]
  public var overflowMenu: TabViewOverflowMenuPresentation?

  public init(
    stripHeight: Int,
    visibleOptionIndices: [Int],
    overflowMenu: TabViewOverflowMenuPresentation?
  ) {
    self.stripHeight = stripHeight
    self.visibleOptionIndices = visibleOptionIndices
    self.overflowMenu = overflowMenu
  }
}

public struct TabViewStyleConfiguration: Sendable {
  public var options: [TabViewStyleOption]
  public var selectedIndex: Int?
  public var focusedIndex: Int?
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var availableWidth: Int
  public var isOverflowMenuExpanded: Bool

  public init(
    options: [TabViewStyleOption],
    selectedIndex: Int?,
    focusedIndex: Int?,
    isFocused: Bool,
    showsFocusEffect: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    availableWidth: Int,
    isOverflowMenuExpanded: Bool
  ) {
    self.options = options
    self.selectedIndex = selectedIndex
    self.focusedIndex = focusedIndex
    self.isFocused = isFocused
    self.showsFocusEffect = showsFocusEffect
    self.styleEnvironment = styleEnvironment
    self.availableWidth = availableWidth
    self.isOverflowMenuExpanded = isOverflowMenuExpanded
  }
}
