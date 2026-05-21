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
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
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
  associatedtype Body: View

  var snapshotLabel: String { get }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @ViewBuilder @MainActor
  func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> Body
}

extension TabViewStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
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
  package var controlIdentity: Identity?

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
    controlIdentity = nil
  }

  package init(
    index: Int,
    label: TabItemLabel,
    isSelected: Bool,
    isFocused: Bool,
    controlIdentity: Identity
  ) {
    self.index = index
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.controlIdentity = controlIdentity
  }

  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabItemIdentity(for: controlIdentity, index: index),
        content: content()
      )
    } else {
      content()
    }
  }

  @ViewBuilder @MainActor
  public func overflowRoute<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabOverflowItemIdentity(for: controlIdentity, index: index),
        content: content()
      )
    } else {
      content()
    }
  }
}

public struct TabViewOverflowTriggerConfiguration: Sendable {
  public var label: String
  public var isSelected: Bool
  public var isFocused: Bool
  public var isExpanded: Bool
  public var overflowIndices: [Int]
  public var leadingWidth: Int
  package var controlIdentity: Identity?

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
    controlIdentity = nil
  }

  package init(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isExpanded: Bool,
    overflowIndices: [Int],
    leadingWidth: Int,
    controlIdentity: Identity
  ) {
    self.label = label
    self.isSelected = isSelected
    self.isFocused = isFocused
    self.isExpanded = isExpanded
    self.overflowIndices = overflowIndices
    self.leadingWidth = leadingWidth
    self.controlIdentity = controlIdentity
  }

  @ViewBuilder @MainActor
  public func route<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if let controlIdentity {
      PointerRouteView(
        identity: tabOverflowTriggerIdentity(for: controlIdentity),
        content: content()
      )
    } else {
      content()
    }
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

public struct TabViewStyleBodyConfiguration: Sendable {
  public struct Content: PrimitiveView, ResolvableView, Sendable {
    package var activeContentIndex: Int?
    package var payload: DeferredViewPayload?

    package init(
      activeContentIndex: Int?,
      payload: DeferredViewPayload?
    ) {
      self.activeContentIndex = activeContentIndex
      self.payload = payload
    }

    package func resolveElements(
      in context: ResolveContext
    ) -> [ResolvedNode] {
      guard let payload else {
        return []
      }

      // Keep the style-owned content slot transparent while preserving the
      // deferred payload boundary that owns active-tab lifecycle and state.
      let child = resolveView(
        DeferredPayloadView(payload: payload),
        in: context.indexedChild(
          kind: .init(rawValue: "TabContentPayload"),
          index: activeContentIndex ?? 0
        )
      )

      return [
        ResolvedNode(
          identity: context.identity,
          kind: .view("Group"),
          children: [child],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction
        )
      ]
    }
  }

  public var options: [TabViewStyleOption]
  public var items: [TabViewStyleItemConfiguration]
  public var visibleItems: [TabViewStyleItemConfiguration]
  public var overflowItems: [TabViewStyleItemConfiguration]
  public var selectedIndex: Int?
  public var focusedIndex: Int?
  public var isFocused: Bool
  public var showsFocusEffect: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot
  public var availableWidth: Int
  public var isOverflowMenuExpanded: Bool
  public var presentation: TabViewStylePresentation
  public var overflowTrigger: TabViewOverflowTriggerConfiguration?
  public var content: Content

  package init(
    styleConfiguration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    items: [TabViewStyleItemConfiguration],
    overflowTrigger: TabViewOverflowTriggerConfiguration?,
    content: Content
  ) {
    options = styleConfiguration.options
    self.items = items
    visibleItems = presentation.visibleOptionIndices.compactMap { index in
      items.indices.contains(index) ? items[index] : nil
    }
    overflowItems =
      presentation.overflowMenu?.overflowIndices.compactMap { index in
        items.indices.contains(index) ? items[index] : nil
      } ?? []
    selectedIndex = styleConfiguration.selectedIndex
    focusedIndex = styleConfiguration.focusedIndex
    isFocused = styleConfiguration.isFocused
    showsFocusEffect = styleConfiguration.showsFocusEffect
    styleEnvironment = styleConfiguration.styleEnvironment
    availableWidth = styleConfiguration.availableWidth
    isOverflowMenuExpanded = styleConfiguration.isOverflowMenuExpanded
    self.presentation = presentation
    self.overflowTrigger = overflowTrigger
    self.content = content
  }
}
