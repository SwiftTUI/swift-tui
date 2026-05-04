import SwiftTUICore

private enum InlinePickerRow {
  case marker(String?)
  case option(index: Int, label: String, isSelected: Bool)
}

package struct MenuPickerStyleBody: View {
  let configuration: PickerStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let triggerChrome = configuration.styleEnvironment.rowChrome(
      isEnabled: configuration.isEnabled,
      isFocused: configuration.isFocused && configuration.showsFocusEffect,
      isSelected: configuration.selectedIndex != nil
    )
    let selectedLabel =
      if let selectedIndex = configuration.selectedIndex,
        configuration.options.indices.contains(selectedIndex)
      {
        configuration.options[selectedIndex].label
      } else {
        "Select"
      }
    let triggerRow = controlFocusRow(
      showsRail: configuration.isFocused,
      railStyle: triggerChrome.borderStyle,
      isHighlighted: configuration.isFocused,
      backgroundStyle: triggerChrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      Text(configuration.isActiveNavigation ? "▴" : "▾")
      Text(selectedLabel)
        .lineLimit(1)
      Spacer()
    }
    .foregroundStyle(triggerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: triggerChrome.opacity))
    .id(pickerTriggerIdentity(for: configuration.controlIdentity))
    .semanticMetadata(.init(participatesInPointerHitTesting: true))

    VStack(alignment: .leading, spacing: 0) {
      configuration.label
        .foregroundStyle(.terminalBorder(.accent))
      triggerRow

      if configuration.isActiveNavigation {
        MenuPickerOptionList(configuration: configuration)
      }
    }
    .foregroundStyle(triggerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: triggerChrome.opacity))
    .layoutMetadata(
      .init(
        minimumHeight: 1 + 1 + (configuration.isActiveNavigation ? configuration.options.count : 0)
      )
    )
  }
}

private struct MenuPickerOptionList: View {
  let configuration: PickerStyleConfiguration

  @MainActor
  var body: some View {
    let rowLineWidth = inlineRowIntrinsicLineWidth(for: configuration.options)
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<configuration.options.count) { index in
        pickerRow(
          label: configuration.options[index].label,
          isSelected: index == configuration.selectedIndex,
          isActiveNavigation: configuration.showsFocusEffect,
          isEnabled: configuration.isEnabled,
          styleEnvironment: configuration.styleEnvironment,
          lineWidth: rowLineWidth,
          routeIdentity: pickerOptionIdentity(
            for: configuration.controlIdentity,
            index: index
          )
        )
      }
    }
    .padding(.init(leading: 1))
  }
}

package struct InlinePickerStyleBody: View {
  let configuration: PickerStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let containerChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled,
      isFocused: configuration.isFocused && configuration.showsFocusEffect
    )
    // Focus is communicated by the thick border overlay; avoid a tinted
    // container fill, which otherwise reads as every row being highlighted.
    let containerFillStyle = AnyShapeStyle(.background)
    let resolvedLineWidth =
      configuration.lineWidth ?? inlineRowIntrinsicLineWidth(for: configuration.options)
    let rows = inlineRows(
      options: configuration.options,
      selectedIndex: configuration.selectedIndex,
      viewportLineCount: configuration.viewportLineCount
    )

    VStack(alignment: .leading, spacing: 0) {
      configuration.label
        .foregroundStyle(.terminalBorder(.accent))
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<rows.count) { index in
          inlineRowView(
            rows[index],
            controlIdentity: configuration.controlIdentity,
            isActiveNavigation: configuration.isActiveNavigation && configuration.showsFocusEffect,
            isEnabled: configuration.isEnabled,
            styleEnvironment: configuration.styleEnvironment,
            lineWidth: resolvedLineWidth
          )
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(containerFillStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          containerChrome.borderStyle,
          style: configuration.isFocused && configuration.showsFocusEffect ? .heavy : .init(),
          background: containerChrome.borderBackgroundStyle
        )
      }
    }
    .foregroundStyle(containerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: containerChrome.opacity))
    .layoutMetadata(
      .init(
        minimumHeight: 1 + rows.count + 2
      )
    )
  }
}

package struct SegmentedPickerStyleBody: View {
  let configuration: PickerStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let containerChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled,
      isFocused: configuration.isFocused && configuration.showsFocusEffect
    )

    VStack(alignment: .leading, spacing: 0) {
      configuration.label
        .foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        ForEach(0..<configuration.options.count) { index in
          segmentedSegmentView(
            option: configuration.options[index],
            index: index,
            configuration: configuration
          )
          if index < configuration.options.count - 1 {
            Divider()
          }
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(containerChrome.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          containerChrome.borderStyle,
          style: configuration.isFocused && configuration.showsFocusEffect ? .heavy : .init(),
          background: containerChrome.borderBackgroundStyle
        )
      }
    }
    .foregroundStyle(containerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: containerChrome.opacity))
  }
}

package struct RadioGroupPickerStyleBody: View {
  let configuration: PickerStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let containerChrome = configuration.styleEnvironment.controlChrome(
      isEnabled: configuration.isEnabled,
      isFocused: configuration.isFocused && configuration.showsFocusEffect
    )

    VStack(alignment: .leading, spacing: 0) {
      configuration.label
        .foregroundStyle(.terminalBorder(.accent))
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<configuration.options.count) { index in
          radioGroupRow(
            label: configuration.options[index].label,
            isSelected: index == configuration.selectedIndex,
            isFocused: configuration.isActiveNavigation
              && configuration.showsFocusEffect
              && index == configuration.selectedIndex,
            isEnabled: configuration.isEnabled,
            styleEnvironment: configuration.styleEnvironment,
            routeIdentity: pickerOptionIdentity(
              for: configuration.controlIdentity,
              index: index
            )
          )
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(containerChrome.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          containerChrome.borderStyle,
          style: configuration.isFocused && configuration.showsFocusEffect ? .heavy : .init(),
          background: containerChrome.borderBackgroundStyle
        )
      }
    }
    .foregroundStyle(containerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: containerChrome.opacity))
    .fixedSize(horizontal: false, vertical: true)
    .layoutMetadata(
      .init(
        minimumHeight: 1 + configuration.options.count + 2
      )
    )
  }
}

/// Intrinsic row width used so every inline/menu option row occupies the
/// same cell width — the selected-row highlight then covers the full row
/// instead of wrapping to the label and leaving a jagged right edge.
@MainActor
private func inlineRowIntrinsicLineWidth(
  for options: [PickerStyleConfiguration.Option]
) -> Int {
  let maxLabelWidth =
    options
    .map { layoutText(for: $0.label, width: nil).size.width }
    .max() ?? 0
  // `controlFocusRail` reserves a single cell for the rail glyph and
  // `controlFocusRow` inserts one cell of spacing between rail and content.
  return maxLabelWidth + 2
}

@MainActor
private func inlineRows(
  options: [PickerStyleConfiguration.Option],
  selectedIndex: Int?,
  viewportLineCount: Int?
) -> [InlinePickerRow] {
  let indexedOptions = Array(options.enumerated())
  let rowOptions: ArraySlice<(offset: Int, element: PickerStyleConfiguration.Option)>
  let topMarker: String?
  let bottomMarker: String?

  if let viewportLineCount,
    viewportLineCount >= 3,
    options.count > max(1, viewportLineCount - 2)
  {
    let visibleOptionCount = max(1, viewportLineCount - 2)
    let currentIndex = min(max(selectedIndex ?? 0, 0), max(0, options.count - 1))
    let offset = min(
      max(0, currentIndex - (visibleOptionCount / 2)),
      max(0, options.count - visibleOptionCount)
    )
    let end = min(options.count, offset + visibleOptionCount)
    rowOptions = indexedOptions[offset..<end]
    topMarker = offset > 0 ? "↑" : nil
    bottomMarker = end < options.count ? "↓" : nil
  } else {
    rowOptions = indexedOptions[indexedOptions.startIndex..<indexedOptions.endIndex]
    topMarker = nil
    bottomMarker = nil
  }

  var rows: [InlinePickerRow] = []

  if viewportLineCount != nil {
    rows.append(.marker(topMarker))
  }

  for option in rowOptions {
    rows.append(
      .option(
        index: option.offset,
        label: option.element.label,
        isSelected: option.offset == selectedIndex
      )
    )
  }

  if viewportLineCount != nil {
    rows.append(.marker(bottomMarker))
  }

  return rows
}

@MainActor
@ViewBuilder
private func inlineRowView(
  _ row: InlinePickerRow,
  controlIdentity: Identity,
  isActiveNavigation: Bool,
  isEnabled: Bool,
  styleEnvironment: StyleEnvironmentSnapshot,
  lineWidth: Int?
) -> some View {
  switch row {
  case .marker(let text):
    pickerMarkerLine(text, lineWidth: lineWidth)
  case .option(let index, let label, let isSelected):
    pickerRow(
      label: label,
      isSelected: isSelected,
      isActiveNavigation: isActiveNavigation,
      isEnabled: isEnabled,
      styleEnvironment: styleEnvironment,
      lineWidth: lineWidth,
      routeIdentity: pickerOptionIdentity(
        for: controlIdentity,
        index: index
      )
    )
  }
}

@MainActor
private func pickerMarkerLine(
  _ text: String?,
  lineWidth: Int?
) -> some View {
  Text(text ?? "")
    .lineLimit(1)
    .foregroundStyle(.separator)
    .frame(width: lineWidth, alignment: .leading)
}

@MainActor
@ViewBuilder
private func pickerRow(
  label: String,
  isSelected: Bool,
  isActiveNavigation: Bool,
  isEnabled: Bool,
  styleEnvironment: StyleEnvironmentSnapshot,
  lineWidth: Int?,
  routeIdentity: Identity? = nil
) -> some View {
  let rowChrome = styleEnvironment.rowChrome(
    isEnabled: isEnabled,
    isFocused: isActiveNavigation && isSelected,
    isSelected: isActiveNavigation && isSelected
  )
  let markerStyle: AnyShapeStyle =
    if isSelected {
      isActiveNavigation ? rowChrome.borderStyle : AnyShapeStyle(.separator)
    } else {
      AnyShapeStyle(.background)
    }
  let labelStyle: AnyShapeStyle =
    if isSelected {
      isActiveNavigation ? rowChrome.foregroundStyle : AnyShapeStyle(.foreground)
    } else {
      AnyShapeStyle(.foreground)
    }
  // Size the row first, then apply the highlight — otherwise
  // `.background` would hug the HStack's natural (text-only) width and
  // leave a jagged right edge. `.frame(alignment: .leading)` pins the
  // rail+label flush left; the background spans the full row width
  // because it's applied to the frame, not to the HStack's natural size.
  let row =
    HStack(alignment: .center, spacing: 1) {
      controlFocusRail(
        isVisible: isSelected,
        style: markerStyle,
        reservesSpaceWhenHidden: true
      )
      Text(label)
        .lineLimit(1)
        .foregroundStyle(labelStyle)
    }
    .frame(width: lineWidth, alignment: .leading)
    .background {
      if isSelected && isActiveNavigation {
        Rectangle().fill(rowChrome.backgroundStyle)
      }
    }
    .drawMetadata(.init(opacity: rowChrome.opacity))

  if let routeIdentity {
    PointerRouteView(
      identity: routeIdentity,
      content: row
    )
  } else {
    row
  }
}

@MainActor
private func segmentedSegmentView(
  option: PickerStyleConfiguration.Option,
  index: Int,
  configuration: PickerStyleConfiguration
) -> some View {
  let isSelected = index == configuration.selectedIndex
  let segmentChrome = configuration.styleEnvironment.controlChrome(
    isEnabled: configuration.isEnabled,
    isFocused: configuration.isActiveNavigation && configuration.showsFocusEffect && isSelected,
    isSelected: isSelected
  )
  return Text(option.label)
    .lineLimit(1)
    .background {
      if isSelected {
        Rectangle().fill(.tint)
      } else if configuration.isActiveNavigation && configuration.showsFocusEffect {
        Rectangle().inset(by: 1).fill(
          segmentChrome.backgroundStyle
        )
      }
    }
    .foregroundStyle(
      isSelected ? segmentChrome.contentBackgroundStyle : segmentChrome.foregroundStyle
    )
    .drawMetadata(.init(opacity: segmentChrome.opacity))
    .id(
      pickerOptionIdentity(
        for: configuration.controlIdentity,
        index: index
      )
    )
    .semanticMetadata(.init(participatesInPointerHitTesting: true))
}

@MainActor
@ViewBuilder
private func radioGroupRow(
  label: String,
  isSelected: Bool,
  isFocused: Bool,
  isEnabled: Bool,
  styleEnvironment: StyleEnvironmentSnapshot,
  routeIdentity: Identity? = nil
) -> some View {
  let rowChrome = styleEnvironment.rowChrome(
    isEnabled: isEnabled,
    isFocused: isFocused,
    isSelected: isFocused
  )
  let row = controlFocusRow(
    showsRail: isSelected,
    railStyle: isFocused ? rowChrome.borderStyle : AnyShapeStyle(.separator),
    isHighlighted: isSelected && isFocused,
    backgroundStyle: rowChrome.backgroundStyle,
    reservesRailSpaceWhenHidden: true
  ) {
    Text(isSelected ? "(*)" : "( )")
      .foregroundStyle(
        isSelected
          ? (isFocused ? rowChrome.borderStyle : AnyShapeStyle(.separator))
          : AnyShapeStyle(.separator)
      )
    Text(label)
      .foregroundStyle(
        isSelected
          ? (isFocused ? rowChrome.foregroundStyle : AnyShapeStyle(.foreground))
          : AnyShapeStyle(.foreground)
      )
    Spacer(minLength: 0)
  }
  .drawMetadata(.init(opacity: rowChrome.opacity))

  if let routeIdentity {
    PointerRouteView(
      identity: routeIdentity,
      content: row
    )
  } else {
    row
  }
}
