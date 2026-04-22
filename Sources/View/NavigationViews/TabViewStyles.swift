package import Core

public struct AnyTabViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTabViewStyleBox

  package init<S: TabViewStyle>(style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyTabViewStyleBox(style: style)
  }

  public init(_ style: AutomaticTabViewStyle) {
    self.init(style: style)
  }

  public init(_ style: UnderlineTabViewStyle) {
    self.init(style: style)
  }

  public init(_ style: LiteralTabsTabViewStyle) {
    self.init(style: style)
  }

  public init(_ style: PowerlineTabViewStyle) {
    self.init(style: style)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  public static var automatic: Self {
    Self(style: AutomaticTabViewStyle())
  }

  public static var underline: Self {
    Self(style: UnderlineTabViewStyle())
  }

  public static var literalTabs: Self {
    Self(style: LiteralTabsTabViewStyle())
  }

  public static var powerline: Self {
    Self(style: PowerlineTabViewStyle())
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
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      presentation: presentation,
      in: context
    )
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

package protocol TabViewStyle: Sendable {
  associatedtype StripBody: View
  associatedtype OverflowBody: View

  var snapshotLabel: String { get }
  @MainActor
  var layout: AnyLayout { get }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @ViewBuilder @MainActor
  func makeStrip(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> StripBody

  @ViewBuilder @MainActor
  func makeOverflow(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> OverflowBody
}

package struct TabViewStyleOption: Sendable {
  package var label: TabItemLabel
  package var contentPayload: DeferredViewPayload?
}

package struct TabViewOverflowMenuPresentation: Sendable {
  package var triggerLeadingWidth: Int
  package var overflowIndices: [Int]
  package var isExpanded: Bool
  package var selectedOverflowIndex: Int?
  package var focusedOverflowIndex: Int?
  package var triggerLabel: String

  package var isTriggerSelected: Bool {
    selectedOverflowIndex != nil
  }

  package var isTriggerFocused: Bool {
    focusedOverflowIndex != nil
  }

  package var preferredOverflowFocusIndex: Int? {
    focusedOverflowIndex ?? selectedOverflowIndex ?? overflowIndices.first
  }
}

package struct TabViewStylePresentation: Sendable {
  package var stripHeight: Int
  package var visibleOptionIndices: [Int]
  package var overflowMenu: TabViewOverflowMenuPresentation?
}

package struct TabViewStyleConfiguration: Sendable {
  package var controlIdentity: Identity
  package var options: [TabViewStyleOption]
  package var selectedIndex: Int?
  package var focusedIndex: Int?
  package var isFocused: Bool
  package var showsFocusEffect: Bool
  package var styleEnvironment: StyleEnvironmentSnapshot
  package var availableWidth: Int
  package var isOverflowMenuExpanded: Bool
}

extension AutomaticTabViewStyle: TabViewStyle {
  package var snapshotLabel: String {
    "AnyTabViewStyle.automatic"
  }

  @MainActor
  package var layout: AnyLayout {
    tabViewContainerAnyLayout
  }

  @MainActor
  package func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 2,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  package func makeStrip(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> UnderlineTabStripView {
    UnderlineTabStripView(
      configuration: configuration,
      presentation: presentation
    )
  }

  @MainActor
  package func makeOverflow(
    configuration _: TabViewStyleConfiguration,
    presentation _: TabViewStylePresentation
  ) -> EmptyView {
    EmptyView()
  }
}

extension UnderlineTabViewStyle: TabViewStyle {
  package var snapshotLabel: String {
    "AnyTabViewStyle.underline"
  }

  @MainActor
  package var layout: AnyLayout {
    tabViewContainerAnyLayout
  }

  @MainActor
  package func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 2,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  package func makeStrip(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> UnderlineTabStripView {
    UnderlineTabStripView(
      configuration: configuration,
      presentation: presentation
    )
  }

  @MainActor
  package func makeOverflow(
    configuration _: TabViewStyleConfiguration,
    presentation _: TabViewStylePresentation
  ) -> EmptyView {
    EmptyView()
  }
}

extension LiteralTabsTabViewStyle: TabViewStyle {
  package var snapshotLabel: String {
    "AnyTabViewStyle.literalTabs"
  }

  @MainActor
  package var layout: AnyLayout {
    tabViewContainerAnyLayout
  }

  @MainActor
  package func presentation(
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
      )
    )

    return .init(
      stripHeight: stripHeight,
      visibleOptionIndices: visibleIndices,
      overflowMenu: overflowMenu
    )
  }

  @MainActor
  package func makeStrip(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> LiteralTabsStripView {
    LiteralTabsStripView(
      configuration: configuration,
      presentation: presentation
    )
  }

  @MainActor
  package func makeOverflow(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> LiteralTabsOverflowSlotView {
    LiteralTabsOverflowSlotView(
      configuration: configuration,
      presentation: presentation
    )
  }
}

extension PowerlineTabViewStyle: TabViewStyle {
  package var snapshotLabel: String {
    "AnyTabViewStyle.powerline"
  }

  @MainActor
  package var layout: AnyLayout {
    tabViewContainerAnyLayout
  }

  @MainActor
  package func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    .init(
      stripHeight: 1,
      visibleOptionIndices: Array(configuration.options.indices),
      overflowMenu: nil
    )
  }

  @MainActor
  package func makeStrip(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation
  ) -> PowerlineTabStripView {
    PowerlineTabStripView(
      configuration: configuration,
      presentation: presentation
    )
  }

  @MainActor
  package func makeOverflow(
    configuration _: TabViewStyleConfiguration,
    presentation _: TabViewStylePresentation
  ) -> EmptyView {
    EmptyView()
  }
}

private protocol AnyTabViewStyleBox: Sendable {
  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func resolveBody(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    in context: ResolveContext
  ) -> ResolvedNode
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
  func resolveBody(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    in context: ResolveContext
  ) -> ResolvedNode {
    TabViewStyleBodyHost(
      layoutBehavior: style.layout.resolvedBehavior,
      strip: style.makeStrip(
        configuration: configuration,
        presentation: presentation
      ),
      activeContentIndex: configuration.selectedIndex,
      activeContent: configuration.selectedIndex.flatMap {
        configuration.options.indices.contains($0) ? configuration.options[$0].contentPayload : nil
      },
      overflow: style.makeOverflow(
        configuration: configuration,
        presentation: presentation
      )
    ).resolve(in: context)
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

private struct TabViewContainerLayout: Layout, MeasurementLayoutReuseProviding {
  var measurementLayoutReuseSignature: String {
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
    let contentChildren =
      activeContent?.resolveElements(
        in: context.indexedChild(
          kind: .init(rawValue: "TabContentPayload"),
          index: activeContentIndex ?? 0
        )
      ) ?? []

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

package struct UnderlineTabStripView: View {
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  package var body: some View {
    tabStripRow(chrome: .underline)
      .frame(height: presentation.stripHeight, alignment: .leading)
  }

  private func tabStripRow(
    chrome: TabStripChromeStyle
  ) -> some View {
    let activeIndex = configuration.selectedIndex ?? 0
    let focusActive = configuration.isFocused && configuration.showsFocusEffect

    return HStack(alignment: .top, spacing: 0) {
      ForEach(presentation.visibleOptionIndices, id: \.self) { index in
        let option = configuration.options[index]
        let trailingSeparatorStyle =
          powerlineSeparatorStyle(
            index: index,
            activeIndex: activeIndex
          )

        TabStripItemView(
          pointerIdentity: tabItemIdentity(
            for: configuration.controlIdentity,
            index: index
          ),
          label: option.label.displayText,
          isSelected: index == activeIndex,
          isFocused: focusActive && index == configuration.focusedIndex,
          showsTrailingSeparator: index < configuration.options.count - 1,
          trailingSeparatorStyle: trailingSeparatorStyle,
          tone: .accent,
          chrome: chrome,
          styleEnvironment: configuration.styleEnvironment
        )
      }
      Spacer(minLength: 0)
    }
  }
}

package struct PowerlineTabStripView: View {
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  package var body: some View {
    let activeIndex = configuration.selectedIndex ?? 0
    let focusActive = configuration.isFocused && configuration.showsFocusEffect

    return HStack(alignment: .top, spacing: 0) {
      ForEach(presentation.visibleOptionIndices, id: \.self) { index in
        let option = configuration.options[index]

        TabStripItemView(
          pointerIdentity: tabItemIdentity(
            for: configuration.controlIdentity,
            index: index
          ),
          label: option.label.displayText,
          isSelected: index == activeIndex,
          isFocused: focusActive && index == configuration.focusedIndex,
          showsTrailingSeparator: index < configuration.options.count - 1,
          trailingSeparatorStyle: powerlineSeparatorStyle(
            index: index,
            activeIndex: activeIndex
          ),
          tone: .accent,
          chrome: .powerline,
          styleEnvironment: configuration.styleEnvironment
        )
      }
      Spacer(minLength: 0)
    }
    .frame(height: presentation.stripHeight, alignment: .leading)
  }
}

package struct LiteralTabsStripView: View {
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  package var body: some View {
    let activeIndex = configuration.selectedIndex ?? 0
    let focusActive = configuration.isFocused && configuration.showsFocusEffect

    return HStack(alignment: .top, spacing: 0) {
      ForEach(presentation.visibleOptionIndices, id: \.self) { index in
        let option = configuration.options[index]

        TabStripItemView(
          pointerIdentity: tabItemIdentity(
            for: configuration.controlIdentity,
            index: index
          ),
          label: option.label.displayText,
          isSelected: index == activeIndex,
          isFocused: focusActive && index == configuration.focusedIndex,
          showsTrailingSeparator: false,
          trailingSeparatorStyle: .plain,
          tone: .accent,
          chrome: .literalTabs,
          styleEnvironment: configuration.styleEnvironment
        )
        .fixedSize(horizontal: true, vertical: true)
      }

      if let overflow = presentation.overflowMenu {
        TabStripItemView(
          pointerIdentity: tabOverflowTriggerIdentity(
            for: configuration.controlIdentity
          ),
          label: overflow.triggerLabel,
          isSelected: overflow.isTriggerSelected,
          isFocused: focusActive && overflow.isTriggerFocused,
          showsTrailingSeparator: false,
          trailingSeparatorStyle: .plain,
          tone: .accent,
          chrome: .literalTabs,
          styleEnvironment: configuration.styleEnvironment
        )
        .fixedSize(horizontal: true, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .frame(height: presentation.stripHeight, alignment: .leading)
    .background {
      VStack(alignment: .leading, spacing: 0) {
        Spacer(minLength: 0)
          .frame(height: presentation.stripHeight - 1)
        Divider(
          drawMetadata: .init(
            foregroundStyle: .semantic(.foreground)
          )
        )
        .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .leading)
      }
    }
  }
}

package struct LiteralTabsOverflowSlotView: View {
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  @ViewBuilder
  package var body: some View {
    if let overflow = presentation.overflowMenu, overflow.isExpanded {
      HStack(alignment: .top, spacing: 0) {
        Spacer(minLength: 0)
          .frame(width: overflow.triggerLeadingWidth)
        LiteralTabsOverflowMenuView(
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

private struct LiteralTabsOverflowMenuView: View {
  let configuration: TabViewStyleConfiguration
  let overflow: TabViewOverflowMenuPresentation

  var body: some View {
    let menuBorderStyle: AnyShapeStyle =
      if configuration.isFocused && configuration.showsFocusEffect {
        AnyShapeStyle(.terminalBorder(.accent))
      } else {
        AnyShapeStyle(.terminalBorder(.neutral))
      }

    VStack(alignment: .leading, spacing: 0) {
      ForEach(overflow.overflowIndices, id: \.self) { index in
        let option = configuration.options[index]
        let isRowSelected = index == configuration.selectedIndex
        let isRowFocused =
          configuration.isFocused
          && configuration.showsFocusEffect
          && index == configuration.focusedIndex
        let rowChrome = configuration.styleEnvironment.rowChrome(
          isEnabled: true,
          isFocused: isRowFocused,
          isSelected: isRowSelected
        )

        let row = controlFocusRow(
          showsRail: isRowFocused || isRowSelected,
          railStyle: rowChrome.borderStyle,
          isHighlighted: isRowFocused || isRowSelected,
          backgroundStyle: rowChrome.backgroundStyle,
          reservesRailSpaceWhenHidden: true
        ) {
          Text(option.label.displayText)
            .lineLimit(1)
        }
        .foregroundStyle(rowChrome.foregroundStyle)
        .drawMetadata(.init(opacity: rowChrome.opacity))
        .frame(
          minWidth: .finite(
            literalTabOverflowMenuWidth(
              options: configuration.options,
              overflowIndices: overflow.overflowIndices
            )
          ),
          alignment: .leading
        )

        PointerRouteView(
          identity: tabOverflowItemIdentity(
            for: configuration.controlIdentity,
            index: index
          ),
          content: row
        )
      }
    }
    .padding(.init(horizontal: 1, vertical: 1))
    .background {
      RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(AnyShapeStyle(.background))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(menuBorderStyle)
    }
    .fixedSize(horizontal: true, vertical: true)
  }
}

private enum TabStripChromeStyle {
  case underline
  case literalTabs
  case powerline
}

private struct TabStripItemView: View {
  let pointerIdentity: Identity
  let label: String
  let isSelected: Bool
  let isFocused: Bool
  let showsTrailingSeparator: Bool
  let trailingSeparatorStyle: PowerlineSeparatorStyle
  let tone: TerminalTone
  let chrome: TabStripChromeStyle
  let styleEnvironment: StyleEnvironmentSnapshot

  var body: some View {
    PointerRouteView(
      identity: pointerIdentity,
      content: VStack(alignment: .leading, spacing: 0) {
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
    )
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
