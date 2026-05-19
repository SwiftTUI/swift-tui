@_spi(Testing) import SwiftTUICore

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
      // Single-line `─` rule that completes the box-drawing tab chrome
      // (╭─╮ │ │ ┴──┴) along the bottom of the strip. Resolved as its own
      // leaf node rather than via `Divider` so we can pin the foreground
      // color to `.foreground` without leaking `DrawMetadata` through a
      // public Divider parameter.
      LiteralTabsStripBaseRule()
        .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1, alignment: .leading)
    }
  }
}

private struct LiteralTabsStripBaseRule: PrimitiveView, ResolvableView {
  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var drawMetadata = DrawMetadata()
    drawMetadata.foregroundStyle = .semantic(.foreground)
    drawMetadata.ruleStackAxis = context.environmentValues.stackAxis
    return [
      resolveLeafNode(
        kindName: "LiteralTabsStripBaseRule",
        intrinsicSize: .init(width: 1, height: 1),
        drawMetadata: drawMetadata,
        drawPayload: .rule(.single),
        in: context
      )
    ]
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

private enum TabStripChromeStyle {
  case underline
  case literalTabs
  case powerline
}

/// FIXME: this view is an indication that TabViewStyle is not powerful enough to do its job.
/// The implementations of each of the styles should be fully independent and there should be
/// no introspection required to lay them out. This construct should go.
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
  isFocused _: Bool,
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
