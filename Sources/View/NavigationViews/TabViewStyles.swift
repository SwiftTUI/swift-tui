public import Core

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
    TabViewStyleBodyHost(
      layoutBehavior: tabViewContainerAnyLayout.resolvedBehavior,
      strip: FrameworkHostedTabStripView(
        styleBox: box,
        controlIdentity: controlIdentity,
        configuration: configuration,
        presentation: presentation
      ),
      activeContentIndex: activeContentIndex,
      activeContent: activeContent,
      overflow: FrameworkHostedTabOverflowSlotView(
        styleBox: box,
        controlIdentity: controlIdentity,
        configuration: configuration,
        presentation: presentation
      )
    ).resolve(in: context)
  }
}

public struct AutomaticTabViewStyle: Sendable {
  public init() {}
}

public struct UnderlineTabViewStyle: Sendable {
  public init() {}
}

public struct LiteralTabsTabViewStyle: Sendable {
  public init() {}
}

public struct PowerlineTabViewStyle: Sendable {
  public init() {}
}

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

extension AutomaticTabViewStyle: TabViewStyle {
  public var snapshotLabel: String {
    "AnyTabViewStyle.automatic"
  }

  @MainActor
  public func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 2,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  public func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> some View {
    UnderlineTabStyleItemView(
      configuration: configuration,
      item: item
    )
  }
}

extension UnderlineTabViewStyle: TabViewStyle {
  public var snapshotLabel: String {
    "AnyTabViewStyle.underline"
  }

  @MainActor
  public func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 2,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  public func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> some View {
    UnderlineTabStyleItemView(
      configuration: configuration,
      item: item
    )
  }
}

extension LiteralTabsTabViewStyle: TabViewStyle {
  public var snapshotLabel: String {
    "AnyTabViewStyle.literalTabs"
  }

  @MainActor
  public func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    let stripHeight = 3
    guard configuration.options.count > 1 else {
      return .init(
        stripHeight: stripHeight,
        visibleOptionIndices: Array(configuration.options.indices),
        overflowMenu: nil
      )
    }

    let tabWidths = configuration.options.map { literalTabWidth(label: $0.label.displayText) }
    let totalWidth = tabWidths.reduce(0, +)
    guard totalWidth > configuration.availableWidth else {
      return .init(
        stripHeight: stripHeight,
        visibleOptionIndices: Array(configuration.options.indices),
        overflowMenu: nil
      )
    }

    let overflowTriggerWidth = literalTabWidth(label: literalTabOverflowCollapsedGlyph)
    var visibleIndices: [Int] = []
    var usedWidth = 0

    for index in configuration.options.indices {
      let remainingCount = configuration.options.count - (index + 1)
      let widthWithCurrentTab = usedWidth + tabWidths[index]
      let requiredWidth =
        widthWithCurrentTab + (remainingCount > 0 ? overflowTriggerWidth : 0)
      if requiredWidth <= configuration.availableWidth {
        visibleIndices.append(index)
        usedWidth = widthWithCurrentTab
      } else {
        break
      }
    }

    let overflowIndices = Array(configuration.options.indices.dropFirst(visibleIndices.count))
    guard !overflowIndices.isEmpty else {
      return .init(
        stripHeight: stripHeight,
        visibleOptionIndices: Array(configuration.options.indices),
        overflowMenu: nil
      )
    }

    let selectedOverflowIndex: Int? =
      if let selectedIndex = configuration.selectedIndex,
        overflowIndices.contains(selectedIndex)
      {
        selectedIndex
      } else {
        nil
      }
    let focusedOverflowIndex: Int? =
      if let focusedIndex = configuration.focusedIndex,
        overflowIndices.contains(focusedIndex)
      {
        focusedIndex
      } else {
        nil
      }

    let overflowMenu = TabViewOverflowMenuPresentation(
      triggerLeadingWidth: usedWidth,
      overflowIndices: overflowIndices,
      isExpanded: configuration.isOverflowMenuExpanded,
      selectedOverflowIndex: selectedOverflowIndex,
      focusedOverflowIndex: focusedOverflowIndex,
      triggerLabel: literalTabOverflowTriggerLabel(
        isExpanded: configuration.isOverflowMenuExpanded,
        isSelected: selectedOverflowIndex != nil
      ),
      contentPadding: .init(horizontal: 1, vertical: 1),
      backgroundStyle: AnyShapeStyle(.background),
      borderStyle: AnyShapeStyle(
        configuration.isFocused && configuration.showsFocusEffect
          ? .terminalBorder(.accent)
          : .terminalBorder(.neutral)
      ),
      borderInset: 1,
      cornerRadius: 1
    )

    return .init(
      stripHeight: stripHeight,
      visibleOptionIndices: visibleIndices,
      overflowMenu: overflowMenu
    )
  }

  @MainActor
  public func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> some View {
    LiteralTabsTabStyleItemView(
      configuration: configuration,
      item: item
    )
  }

  @MainActor
  public func makeOverflowTriggerBody(
    configuration: TabViewStyleConfiguration,
    trigger: TabViewOverflowTriggerConfiguration
  ) -> some View {
    LiteralTabsOverflowTriggerView(
      configuration: configuration,
      trigger: trigger
    )
  }

  @MainActor
  public func makeOverflowItemBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration,
    overflow: TabViewOverflowMenuPresentation
  ) -> some View {
    LiteralTabsOverflowMenuRowView(
      configuration: configuration,
      item: item,
      overflowIndices: overflow.overflowIndices
    )
  }

  @MainActor
  public func makeStripBackground(
    configuration _: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> some View {
    LiteralTabsStripBackgroundView(presentation: presentation)
  }
}

extension PowerlineTabViewStyle: TabViewStyle {
  public var snapshotLabel: String {
    "AnyTabViewStyle.powerline"
  }

  @MainActor
  public func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  public func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> some View {
    PowerlineTabStyleItemView(
      configuration: configuration,
      item: item
    )
  }
}

private protocol AnyTabViewStyleBox: Sendable {
  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> AnyView

  @MainActor
  func makeOverflowTriggerBody(
    configuration: TabViewStyleConfiguration,
    trigger: TabViewOverflowTriggerConfiguration
  ) -> AnyView

  @MainActor
  func makeOverflowItemBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration,
    overflow: TabViewOverflowMenuPresentation
  ) -> AnyView

  @MainActor
  func makeStripBackground(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> AnyView
}

private struct ConcreteAnyTabViewStyleBox<S: TabViewStyle>: AnyTabViewStyleBox {
  let style: S

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    style.presentation(for: configuration)
  }

  @MainActor
  func makeTabBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration
  ) -> AnyView {
    AnyView(
      style.makeTabBody(
        configuration: configuration,
        item: item
      )
    )
  }

  @MainActor
  func makeOverflowTriggerBody(
    configuration: TabViewStyleConfiguration,
    trigger: TabViewOverflowTriggerConfiguration
  ) -> AnyView {
    AnyView(
      style.makeOverflowTriggerBody(
        configuration: configuration,
        trigger: trigger
      )
    )
  }

  @MainActor
  func makeOverflowItemBody(
    configuration: TabViewStyleConfiguration,
    item: TabViewStyleItemConfiguration,
    overflow: TabViewOverflowMenuPresentation
  ) -> AnyView {
    AnyView(
      style.makeOverflowItemBody(
        configuration: configuration,
        item: item,
        overflow: overflow
      )
    )
  }

  @MainActor
  func makeStripBackground(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> AnyView {
    AnyView(
      style.makeStripBackground(
        configuration: configuration,
        presentation: presentation
      )
    )
  }
}

private enum TabViewLayoutSubviewRole: String, Sendable {
  case strip
  case content
  case overflow
}

private enum TabViewLayoutSubviewRoleKey: LayoutValueKey {
  static let defaultValue = TabViewLayoutSubviewRole.content
}

@MainActor
private let tabViewContainerAnyLayout = AnyLayout(TabViewContainerLayout())

private struct TabViewContainerLayout: SendableLayout {
  var measurementReuseSignature: String {
    "TabViewContainerLayout"
  }

  var placementReuseSignature: String {
    "TabViewContainerLayout"
  }

  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let stripSubview = subview(role: .strip, in: subviews)
    let contentSubview = subview(role: .content, in: subviews)

    let stripSize =
      stripSubview?.sizeThatFits(
        .init(width: proposal.width, height: .unspecified)
      ) ?? .zero
    let contentSize =
      contentSubview?.sizeThatFits(
        .init(
          width: proposal.width,
          height: reducedDimension(proposal.height, by: stripSize.height)
        )
      ) ?? .zero

    return .init(
      width: max(stripSize.width, contentSize.width),
      height: stripSize.height + contentSize.height
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let stripSubview = subview(role: .strip, in: subviews)
    let contentSubview = subview(role: .content, in: subviews)
    let overflowSubview = subview(role: .overflow, in: subviews)

    let stripSize =
      stripSubview?.sizeThatFits(
        .init(width: .finite(bounds.size.width), height: .unspecified)
      ) ?? .zero

    stripSubview?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(stripSize.height)
      )
    )

    contentSubview?.place(
      at: .init(
        x: bounds.origin.x,
        y: bounds.origin.y + stripSize.height
      ),
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(max(0, bounds.size.height - stripSize.height))
      )
    )

    overflowSubview?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(bounds.size.height)
      )
    )
  }

  private func subview(
    role: TabViewLayoutSubviewRole,
    in subviews: LayoutSubviews
  ) -> LayoutSubview? {
    subviews.first { $0[TabViewLayoutSubviewRoleKey.self] == role }
  }

  private func reducedDimension(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      .unspecified
    case .finite(let value):
      .finite(max(0, value - amount))
    case .infinity:
      .infinity
    }
  }
}

private struct TabViewStyleBodyHost<Strip: View, Overflow: View>: View, ResolvableView {
  let layoutBehavior: LayoutBehavior
  let strip: Strip
  let activeContentIndex: Int?
  let activeContent: DeferredViewPayload?
  let overflow: Overflow

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let stripNode = strip.resolve(
      in: context.child(component: .named("strip-view"))
    )
    let overflowNode = overflow.resolve(
      in: context.child(component: .named("overflow-view"))
    )
    let contentChildren: [ResolvedNode]
    if let activeContent {
      contentChildren = [
        resolveView(
          DeferredPayloadView(payload: activeContent),
          in: context.indexedChild(
            kind: .init(rawValue: "TabContentPayload"),
            index: activeContentIndex ?? 0
          )
        )
      ]
    } else {
      contentChildren = []
    }

    let stripSlot = TabViewLayoutSlotNode(
      kindName: "TabStripSlot",
      role: .strip,
      children: [stripNode]
    ).resolve(
      in: context.child(component: .named("strip-slot"))
    )
    let contentSlot = TabViewLayoutSlotNode(
      kindName: "TabContentSlot",
      role: .content,
      layoutBehavior: .flexibleFrame(
        minWidth: nil,
        idealWidth: nil,
        maxWidth: .infinity,
        minHeight: nil,
        idealHeight: nil,
        maxHeight: .infinity,
        alignment: .topLeading
      ),
      children: contentChildren
    ).resolve(
      in: context.child(component: .named("content-slot"))
    )
    let overflowSlot = TabViewLayoutSlotNode(
      kindName: "TabOverflowSlot",
      role: .overflow,
      children: [overflowNode]
    ).resolve(
      in: context.child(component: .named("overflow-slot"))
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("TabViewStyleBody"),
        children: [stripSlot, contentSlot, overflowSlot],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layoutBehavior
      )
    ]
  }
}

private struct TabViewLayoutSlotNode: View, ResolvableView {
  let kindName: String
  let role: TabViewLayoutSubviewRole
  var layoutBehavior: LayoutBehavior = .intrinsic
  var children: [ResolvedNode]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let layoutMetadata = LayoutMetadata().settingLayoutValue(
      role,
      for: ObjectIdentifier(TabViewLayoutSubviewRoleKey.self),
      debugName: String(reflecting: TabViewLayoutSubviewRoleKey.self),
      debugValue: role.rawValue
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view(kindName),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layoutBehavior,
        layoutMetadata: layoutMetadata
      )
    ]
  }
}

private struct FrameworkHostedTabStripView: View {
  let styleBox: any AnyTabViewStyleBox
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(presentation.visibleOptionIndices, id: \.self) { index in
        PointerRouteView(
          identity: tabItemIdentity(
            for: controlIdentity,
            index: index
          ),
          content: styleBox.makeTabBody(
            configuration: configuration,
            item: tabStyleItemConfiguration(
              for: configuration,
              index: index
            )
          )
        )
      }

      if let overflow = presentation.overflowMenu {
        PointerRouteView(
          identity: tabOverflowTriggerIdentity(for: controlIdentity),
          content: styleBox.makeOverflowTriggerBody(
            configuration: configuration,
            trigger: tabOverflowTriggerConfiguration(for: overflow)
          )
        )
      }

      Spacer(minLength: 0)
    }
    .frame(height: presentation.stripHeight, alignment: .leading)
    .background {
      styleBox.makeStripBackground(
        configuration: configuration,
        presentation: presentation
      )
    }
  }
}

private struct FrameworkHostedTabOverflowSlotView: View {
  let styleBox: any AnyTabViewStyleBox
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  @ViewBuilder
  var body: some View {
    if let overflow = presentation.overflowMenu, overflow.isExpanded {
      HStack(alignment: .top, spacing: 0) {
        Spacer(minLength: 0)
          .frame(width: overflow.triggerLeadingWidth)
        FrameworkHostedTabOverflowMenuView(
          styleBox: styleBox,
          controlIdentity: controlIdentity,
          configuration: configuration,
          overflow: overflow
        )
        Spacer(minLength: 0)
      }
      .padding(
        .init(
          top: presentation.stripHeight,
          leading: 0,
          bottom: 0,
          trailing: 0
        )
      )
    } else {
      EmptyView()
    }
  }
}

private struct FrameworkHostedTabOverflowMenuView: View {
  let styleBox: any AnyTabViewStyleBox
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let overflow: TabViewOverflowMenuPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(overflow.overflowIndices, id: \.self) { index in
        PointerRouteView(
          identity: tabOverflowItemIdentity(
            for: controlIdentity,
            index: index
          ),
          content: styleBox.makeOverflowItemBody(
            configuration: configuration,
            item: tabStyleItemConfiguration(
              for: configuration,
              index: index
            ),
            overflow: overflow
          )
        )
      }
    }
    .padding(overflow.contentPadding)
    .background {
      if let backgroundStyle = overflow.backgroundStyle {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .inset(by: overflow.borderInset)
          .fill(backgroundStyle)
      }
    }
    .overlay {
      if let borderStyle = overflow.borderStyle {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .chromeStrokeBorder(borderStyle)
      }
    }
    .fixedSize(horizontal: true, vertical: true)
  }
}

private struct UnderlineTabStyleItemView: View {
  let configuration: TabViewStyleConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    TabStripItemView(
      label: item.label.displayText,
      isSelected: item.isSelected,
      isFocused: item.isFocused,
      showsTrailingSeparator: item.index < configuration.options.count - 1,
      trailingSeparatorStyle: powerlineSeparatorStyle(
        index: item.index,
        activeIndex: configuration.selectedIndex ?? 0
      ),
      tone: .accent,
      chrome: .underline,
      styleEnvironment: configuration.styleEnvironment
    )
  }
}

private struct PowerlineTabStyleItemView: View {
  let configuration: TabViewStyleConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    TabStripItemView(
      label: item.label.displayText,
      isSelected: item.isSelected,
      isFocused: item.isFocused,
      showsTrailingSeparator: item.index < configuration.options.count - 1,
      trailingSeparatorStyle: powerlineSeparatorStyle(
        index: item.index,
        activeIndex: configuration.selectedIndex ?? 0
      ),
      tone: .accent,
      chrome: .powerline,
      styleEnvironment: configuration.styleEnvironment
    )
  }
}

private struct LiteralTabsTabStyleItemView: View {
  let configuration: TabViewStyleConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    TabStripItemView(
      label: item.label.displayText,
      isSelected: item.isSelected,
      isFocused: item.isFocused,
      showsTrailingSeparator: false,
      trailingSeparatorStyle: .plain,
      tone: .accent,
      chrome: .literalTabs,
      styleEnvironment: configuration.styleEnvironment
    )
    .fixedSize(horizontal: true, vertical: true)
  }
}

private struct LiteralTabsOverflowTriggerView: View {
  let configuration: TabViewStyleConfiguration
  let trigger: TabViewOverflowTriggerConfiguration

  var body: some View {
    TabStripItemView(
      label: trigger.label,
      isSelected: trigger.isSelected,
      isFocused: trigger.isFocused,
      showsTrailingSeparator: false,
      trailingSeparatorStyle: .plain,
      tone: .accent,
      chrome: .literalTabs,
      styleEnvironment: configuration.styleEnvironment
    )
    .fixedSize(horizontal: true, vertical: true)
  }
}

private struct LiteralTabsStripBackgroundView: View {
  let presentation: TabViewStylePresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
        .frame(height: presentation.stripHeight - 1)
      Divider(
        drawMetadata: .init(
          foregroundStyle: .semantic(.foreground),
          // Use single-line glyphs to stay visually consistent with the
          // box-drawing tab chrome (╭─╮ │ │ ┴──┴).
          borderStrokeStyle: StrokeStyle(borderSet: .single)
        )
      )
      .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .leading)
    }
  }
}

private struct LiteralTabsOverflowMenuRowView: View {
  let configuration: TabViewStyleConfiguration
  let item: TabViewStyleItemConfiguration
  let overflowIndices: [Int]

  var body: some View {
    let rowChrome = configuration.styleEnvironment.rowChrome(
      isEnabled: true,
      isFocused: item.isFocused,
      isSelected: item.isSelected
    )

    return controlFocusRow(
      showsRail: item.isFocused || item.isSelected,
      railStyle: rowChrome.borderStyle,
      isHighlighted: item.isFocused || item.isSelected,
      backgroundStyle: rowChrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      Text(item.label.displayText)
        .lineLimit(1)
    }
    .foregroundStyle(rowChrome.foregroundStyle)
    .drawMetadata(.init(opacity: rowChrome.opacity))
    .frame(
      minWidth: .finite(
        literalTabOverflowMenuWidth(
          options: configuration.options,
          overflowIndices: overflowIndices
        )
      ),
      alignment: .leading
    )
  }
}

private func tabStyleItemConfiguration(
  for configuration: TabViewStyleConfiguration,
  index: Int
) -> TabViewStyleItemConfiguration {
  let focusActive = configuration.isFocused && configuration.showsFocusEffect
  let label =
    if configuration.options.indices.contains(index) {
      configuration.options[index].label
    } else {
      TabItemLabel("Tab \(index + 1)")
    }

  return .init(
    index: index,
    label: label,
    isSelected: configuration.selectedIndex == index,
    isFocused: focusActive && configuration.focusedIndex == index
  )
}

private func tabOverflowTriggerConfiguration(
  for overflow: TabViewOverflowMenuPresentation
) -> TabViewOverflowTriggerConfiguration {
  .init(
    label: overflow.triggerLabel,
    isSelected: overflow.isTriggerSelected,
    isFocused: overflow.isTriggerFocused,
    isExpanded: overflow.isExpanded,
    overflowIndices: overflow.overflowIndices,
    leadingWidth: overflow.triggerLeadingWidth
  )
}

private enum TabStripChromeStyle {
  case underline
  case literalTabs
  case powerline
}

private struct TabStripItemView: View {
  let label: String
  let isSelected: Bool
  let isFocused: Bool
  let showsTrailingSeparator: Bool
  let trailingSeparatorStyle: PowerlineSeparatorStyle
  let tone: TerminalTone
  let chrome: TabStripChromeStyle
  let styleEnvironment: StyleEnvironmentSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      tabItemPrimaryChrome(
        label: label,
        isSelected: isSelected,
        isFocused: isFocused,
        showsTrailingSeparator: showsTrailingSeparator,
        trailingSeparatorStyle: trailingSeparatorStyle,
        tone: tone,
        chrome: chrome,
        styleEnvironment: styleEnvironment
      )
      if chrome != .powerline {
        tabItemRuleChrome(
          label: label,
          isSelected: isSelected,
          isFocused: isFocused,
          tone: tone,
          chrome: chrome,
          styleEnvironment: styleEnvironment
        )
      }
      if chrome == .literalTabs {
        literalTabBottomChrome(
          label: label,
          isSelected: isSelected,
          tone: tone
        )
      }
    }
    .background {
      if isFocused {
        Rectangle()
          .fill(AnyShapeStyle(.terminalSurface(tone)))
      }
    }
  }
}

@MainActor
@ViewBuilder
private func tabItemPrimaryChrome(
  label: String,
  isSelected: Bool,
  isFocused: Bool,
  showsTrailingSeparator: Bool,
  trailingSeparatorStyle: PowerlineSeparatorStyle,
  tone: TerminalTone,
  chrome: TabStripChromeStyle,
  styleEnvironment: StyleEnvironmentSnapshot
) -> some View {
  switch chrome {
  case .underline:
    underlineTabItem(
      label: label,
      isSelected: isSelected,
      tone: tone
    )
  case .literalTabs:
    literalTabItem(label: label)
  case .powerline:
    powerlineTabItem(
      label: label,
      isSelected: isSelected,
      showsTrailingSeparator: showsTrailingSeparator,
      trailingSeparatorStyle: trailingSeparatorStyle,
      tone: tone,
      styleEnvironment: styleEnvironment
    )
  }
}

@MainActor
@ViewBuilder
private func tabItemRuleChrome(
  label: String,
  isSelected: Bool,
  isFocused: Bool,
  tone: TerminalTone,
  chrome: TabStripChromeStyle,
  styleEnvironment _: StyleEnvironmentSnapshot
) -> some View {
  switch chrome {
  case .underline:
    underlineRuleSegment(
      label: label,
      isSelected: isSelected,
      isFocused: isFocused,
      tone: tone
    )
  case .literalTabs:
    literalTabRuleSegment(
      label: label,
      isSelected: isSelected,
      tone: tone
    )
  case .powerline:
    EmptyView()
  }
}

@MainActor
private func underlineTabItem(
  label: String,
  isSelected: Bool,
  tone: TerminalTone
) -> some View {
  let foreground: AnyShapeStyle =
    if isSelected {
      AnyShapeStyle(.terminalAccent(tone))
    } else {
      .semantic(.foreground)
    }

  return Text("\(label) ")
    .lineLimit(1)
    .foregroundStyle(foreground)
    .drawMetadata(.init(opacity: 1.0))
}

@MainActor
private func underlineRuleSegment(
  label: String,
  isSelected: Bool,
  isFocused: Bool,
  tone: TerminalTone
) -> some View {
  let width = tabLabelCellWidth(label)
  let glyph: Character =
    if isSelected && isFocused {
      "▄"
    } else if isSelected || isFocused {
      "▂"
    } else {
      "▁"
    }
  let foreground: AnyShapeStyle =
    if isSelected {
      AnyShapeStyle(.terminalAccent(tone))
    } else if isFocused {
      .semantic(.foreground)
    } else {
      .semantic(.separator)
    }

  return Text("\(String(repeating: glyph, count: width)) ")
    .lineLimit(1)
    .foregroundStyle(foreground)
    .frame(height: 1, alignment: .leading)
}

@MainActor
private func literalTabItem(
  label: String
) -> some View {
  let interiorWidth = tabLabelCellWidth(label) + 2
  let topText = "╭" + String(repeating: "─", count: interiorWidth) + "╮"

  return Text(topText)
    .lineLimit(1)
    .foregroundStyle(AnyShapeStyle(.foreground))
    .drawMetadata(.init(opacity: 1.0))
}

@MainActor
private func literalTabRuleSegment(
  label: String,
  isSelected: Bool,
  tone: TerminalTone
) -> some View {
  let labelForeground: AnyShapeStyle =
    if isSelected {
      AnyShapeStyle(.terminalAccent(tone))
    } else {
      .semantic(.foreground)
    }

  return HStack(alignment: .top, spacing: 0) {
    Text("│ ")
      .lineLimit(1)
      .foregroundStyle(AnyShapeStyle(.foreground))
      .drawMetadata(.init(opacity: 1.0))
    Text(label)
      .lineLimit(1)
      .foregroundStyle(labelForeground)
      .drawMetadata(.init(opacity: 1.0))
    Text(" │")
      .lineLimit(1)
      .foregroundStyle(AnyShapeStyle(.foreground))
      .drawMetadata(.init(opacity: 1.0))
  }
  .frame(height: 1, alignment: .leading)
}

@MainActor
private func literalTabBottomChrome(
  label: String,
  isSelected: Bool,
  tone _: TerminalTone
) -> some View {
  let interiorWidth = tabLabelCellWidth(label) + 2
  let text =
    if isSelected {
      "┘" + String(repeating: " ", count: interiorWidth) + "└"
    } else {
      "┴" + String(repeating: "─", count: interiorWidth) + "┴"
    }

  return Text(text)
    .lineLimit(1)
    .foregroundStyle(AnyShapeStyle(.foreground))
    .drawMetadata(.init(opacity: 1.0))
    .frame(height: 1, alignment: .leading)
}

@MainActor
private func powerlineTabItem(
  label: String,
  isSelected: Bool,
  showsTrailingSeparator: Bool,
  trailingSeparatorStyle: PowerlineSeparatorStyle,
  tone: TerminalTone,
  styleEnvironment: StyleEnvironmentSnapshot
) -> some View {
  let selectedBackgroundColor = powerlineSelectedBackgroundColor(
    tone: tone,
    styleEnvironment: styleEnvironment
  )
  let selectedBackgroundStyle = AnyShapeStyle(selectedBackgroundColor)
  let selectedForegroundStyle = AnyShapeStyle(
    contrastingForegroundColor(on: selectedBackgroundColor)
  )
  let foreground: AnyShapeStyle =
    if isSelected {
      selectedForegroundStyle
    } else {
      .semantic(.foreground)
    }
  let separatorForeground: AnyShapeStyle =
    trailingSeparatorStyle == .plain
    ? .semantic(.separator)
    : selectedBackgroundStyle

  return HStack(alignment: .top, spacing: 0) {
    Text("\(label) ")
      .lineLimit(1)
      .foregroundStyle(foreground)
      .background {
        if isSelected {
          Rectangle().fill(selectedBackgroundStyle)
        }
      }
      .drawMetadata(.init(opacity: 1.0))
    if showsTrailingSeparator {
      Text(trailingSeparatorStyle.glyph)
        .lineLimit(1)
        .foregroundStyle(separatorForeground)
        .drawMetadata(.init(opacity: trailingSeparatorStyle.opacity))
    }
  }
}

private enum PowerlineSeparatorStyle {
  case plain
  case selectedLeading
  case selectedTrailing

  var glyph: String {
    switch self {
    case .plain:
      "╱"
    case .selectedLeading:
      "◢"
    case .selectedTrailing:
      "◤"
    }
  }

  var opacity: Double {
    switch self {
    case .plain:
      0.6
    case .selectedLeading, .selectedTrailing:
      1.0
    }
  }
}

private func powerlineSeparatorStyle(
  index: Int,
  activeIndex: Int
) -> PowerlineSeparatorStyle {
  if index == activeIndex {
    .selectedTrailing
  } else if index + 1 == activeIndex {
    .selectedLeading
  } else {
    .plain
  }
}

private func powerlineSelectedBackgroundColor(
  tone: TerminalTone,
  styleEnvironment: StyleEnvironmentSnapshot
) -> Color {
  switch tone {
  case .accent:
    styleEnvironment.appearance.tintColor
  case .info:
    styleEnvironment.theme.color(for: .info)
  case .success:
    styleEnvironment.theme.color(for: .success)
  case .warning:
    styleEnvironment.theme.color(for: .warning)
  case .danger:
    styleEnvironment.theme.color(for: .danger)
  case .neutral:
    styleEnvironment.theme.color(for: .selection)
  }
}

private func contrastingForegroundColor(
  on backgroundColor: Color
) -> Color {
  let whiteContrast = Color.white.contrastRatio(to: backgroundColor)
  let blackContrast = Color.black.contrastRatio(to: backgroundColor)
  return whiteContrast >= blackContrast ? .white : .black
}

private func tabLabelCellWidth(
  _ label: String
) -> Int {
  layoutText(for: label, width: nil).size.width
}

private let literalTabOverflowCollapsedGlyph = "▾"
private let literalTabOverflowExpandedGlyph = "▴"
private let literalTabOverflowSelectedGlyph = "▼"
private let literalTabOverflowExpandedSelectedGlyph = "▲"

private func literalTabOverflowTriggerLabel(
  isExpanded: Bool,
  isSelected: Bool
) -> String {
  switch (isExpanded, isSelected) {
  case (false, false):
    literalTabOverflowCollapsedGlyph
  case (true, false):
    literalTabOverflowExpandedGlyph
  case (false, true):
    literalTabOverflowSelectedGlyph
  case (true, true):
    literalTabOverflowExpandedSelectedGlyph
  }
}

private func literalTabOverflowMenuWidth(
  options: [TabViewStyleOption],
  overflowIndices: [Int]
) -> Int {
  let maxLabelWidth =
    overflowIndices
    .map { tabLabelCellWidth(options[$0].label.displayText) }
    .max() ?? 0
  return maxLabelWidth + 2
}

private func literalTabWidth(
  label: String
) -> Int {
  tabLabelCellWidth(label) + 4
}

package func tabItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabItem", index: index))
}

package func tabOverflowTriggerIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(.named("TabOverflowTrigger"))
}

package func tabOverflowItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabOverflowItem", index: index))
}
