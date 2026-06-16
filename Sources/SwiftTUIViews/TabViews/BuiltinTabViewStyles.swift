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
  public func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    UnderlineTabStyleBody(configuration: configuration)
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
  public func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    UnderlineTabStyleBody(configuration: configuration)
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
  public func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    LiteralTabsTabStyleBody(configuration: configuration)
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
  public func makeBody(
    configuration: TabViewStyleBodyConfiguration
  ) -> some View {
    PowerlineTabStyleBody(configuration: configuration)
  }
}

private struct UnderlineTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            UnderlineTabStyleItemView(
              configuration: configuration,
              item: item
            )
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}

private struct PowerlineTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
          let item = configuration.visibleItems[index]
          item.route {
            PowerlineTabStyleItemView(
              configuration: configuration,
              item: item
            )
          }
        }
        Spacer(minLength: 0)
      }
      .frame(height: configuration.presentation.stripHeight, alignment: .leading)

      configuration.content
    }
  }
}

private struct LiteralTabsTabStyleBody: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 0) {
          ForEach(Array(configuration.visibleItems.indices), id: \.self) { index in
            let item = configuration.visibleItems[index]
            item.route {
              LiteralTabsTabStyleItemView(
                configuration: configuration,
                item: item
              )
            }
          }

          if let trigger = configuration.overflowTrigger {
            trigger.route {
              LiteralTabsOverflowTriggerView(
                configuration: configuration,
                trigger: trigger
              )
            }
          }

          Spacer(minLength: 0)
        }
        .frame(height: configuration.presentation.stripHeight, alignment: .leading)
        .background {
          LiteralTabsStripBackgroundView(presentation: configuration.presentation)
        }

        configuration.content
      }

      if configuration.overflowTrigger?.isExpanded == true {
        HStack(alignment: .top, spacing: 0) {
          Spacer(minLength: 0)
            .frame(width: literalTabsOverflowMenuLeadingWidth(configuration: configuration))
          LiteralTabsOverflowMenuView(configuration: configuration)
          Spacer(minLength: 0)
        }
        .padding(
          .init(
            top: configuration.presentation.stripHeight,
            leading: 0,
            bottom: 0,
            trailing: 0
          )
        )
      }
    }
  }
}

private struct UnderlineTabStyleItemView: View {
  let configuration: TabViewStyleBodyConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      underlineTabItem(
        label: item.label.displayText,
        isSelected: item.isSelected,
        tone: .accent
      )
      underlineRuleSegment(
        label: item.label.displayText,
        isSelected: item.isSelected,
        isFocused: item.isFocused,
        tone: .accent
      )
    }
    .background {
      if item.isFocused {
        Rectangle()
          .fill(AnyShapeStyle(.terminalSurface(.accent)))
      }
    }
  }
}

private struct PowerlineTabStyleItemView: View {
  let configuration: TabViewStyleBodyConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    powerlineTabItem(
      label: item.label.displayText,
      isSelected: item.isSelected,
      showsTrailingSeparator: item.index < configuration.items.count - 1,
      trailingSeparatorStyle: powerlineSeparatorStyle(
        index: item.index,
        activeIndex: configuration.selectedIndex ?? 0
      ),
      tone: .accent,
      styleEnvironment: configuration.styleEnvironment
    )
    .background {
      if item.isFocused {
        Rectangle()
          .fill(AnyShapeStyle(.terminalSurface(.accent)))
      }
    }
  }
}

private struct LiteralTabsTabStyleItemView: View {
  let configuration: TabViewStyleBodyConfiguration
  let item: TabViewStyleItemConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      literalTabItem(label: item.label.displayText)
      literalTabRuleSegment(
        label: item.label.displayText,
        isSelected: item.isSelected,
        tone: .accent
      )
      literalTabBottomChrome(
        label: item.label.displayText,
        isSelected: item.isSelected,
        tone: .accent
      )
    }
    .background {
      if item.isFocused {
        Rectangle()
          .fill(AnyShapeStyle(.terminalSurface(.accent)))
      }
    }
    .fixedSize(horizontal: true, vertical: true)
  }
}

private struct LiteralTabsOverflowTriggerView: View {
  let configuration: TabViewStyleBodyConfiguration
  let trigger: TabViewOverflowTriggerConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      literalTabItem(label: trigger.label)
      literalTabRuleSegment(
        label: trigger.label,
        isSelected: trigger.isSelected,
        tone: .accent
      )
      literalTabBottomChrome(
        label: trigger.label,
        isSelected: trigger.isSelected,
        tone: .accent
      )
    }
    .background {
      if trigger.isFocused {
        Rectangle()
          .fill(AnyShapeStyle(.terminalSurface(.accent)))
      }
    }
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
  let configuration: TabViewStyleBodyConfiguration
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

private struct LiteralTabsOverflowMenuView: View {
  let configuration: TabViewStyleBodyConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(configuration.overflowItems.indices), id: \.self) { index in
        let item = configuration.overflowItems[index]
        item.overflowRoute {
          LiteralTabsOverflowMenuRowView(
            configuration: configuration,
            item: item,
            overflowIndices: configuration.presentation.overflowMenu?.overflowIndices ?? []
          )
        }
      }
    }
    .padding(configuration.presentation.overflowMenu?.contentPadding ?? .zero)
    .background {
      if let overflow = configuration.presentation.overflowMenu,
        let backgroundStyle = overflow.backgroundStyle
      {
        Rectangle()
          .fill(backgroundStyle)
      }
    }
    .overlay {
      if let overflow = configuration.presentation.overflowMenu,
        let borderStyle = overflow.borderStyle
      {
        if let backgroundStyle = overflow.backgroundStyle {
          RoundedRectangle(cornerRadius: overflow.cornerRadius)
            .strokeBorder(borderStyle, background: backgroundStyle)
        } else {
          RoundedRectangle(cornerRadius: overflow.cornerRadius)
            .strokeBorder(borderStyle)
        }
      }
    }
    .fixedSize(horizontal: true, vertical: true)
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

private func literalTabsOverflowMenuLeadingWidth(
  configuration: TabViewStyleBodyConfiguration
) -> Int {
  guard let trigger = configuration.overflowTrigger,
    let overflow = configuration.presentation.overflowMenu
  else {
    return 0
  }

  let menuWidth =
    literalTabOverflowMenuWidth(
      options: configuration.options,
      overflowIndices: overflow.overflowIndices
    ) + overflow.contentPadding.horizontal
  let triggerTrailingEdge = trigger.leadingWidth + literalTabWidth(label: trigger.label)
  let rightAlignedLeading = triggerTrailingEdge - menuWidth
  let maxLeading = configuration.availableWidth - menuWidth
  return max(0, min(rightAlignedLeading, maxLeading))
}

private func literalTabWidth(
  label: String
) -> Int {
  tabLabelCellWidth(label) + 4
}
