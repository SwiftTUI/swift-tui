import Core

extension Picker {
  private enum InlinePickerRow {
    case marker(String?)
    case option(index: Int, label: String, isSelected: Bool)
  }

  @ViewBuilder
  func pickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    pickerStyle: PickerStyle,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> some View {
    switch pickerStyle {
    case .segmented:
      segmentedPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        styleEnvironment: styleEnvironment
      )
    case .radioGroup:
      radioGroupPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        styleEnvironment: styleEnvironment
      )
    case .menu:
      menuPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        styleEnvironment: styleEnvironment
      )
    case .inline, .automatic:
      inlinePickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        styleEnvironment: styleEnvironment,
        viewportLineCount: viewportLineCount,
        lineWidth: lineWidth
      )
    }
  }

  @ViewBuilder
  private func menuPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let triggerChrome = styleEnvironment.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: selectedIndex != nil
    )
    let selectedLabel =
      if let selectedIndex, options.indices.contains(selectedIndex) {
        options[selectedIndex].label
      } else {
        "Select"
      }
    let triggerRow = controlFocusRow(
      showsRail: isFocused,
      railStyle: triggerChrome.borderStyle,
      isHighlighted: isFocused,
      backgroundStyle: triggerChrome.backgroundStyle,
      reservesRailSpaceWhenHidden: true
    ) {
      Text(isActiveNavigation ? "▴" : "▾")
      Text(selectedLabel)
        .lineLimit(1)
      Spacer()
    }
    .foregroundStyle(triggerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: triggerChrome.opacity))
    .id(pickerTriggerIdentity(for: controlIdentity))
    .semanticMetadata(.init(participatesInPointerHitTesting: true))

    VStack(alignment: .leading, spacing: 0) {
      label
        .foregroundStyle(.terminalBorder(.accent))
      triggerRow

      if isActiveNavigation {
        menuPickerOptionList(
          controlIdentity: controlIdentity,
          options: options,
          selectedIndex: selectedIndex,
          showsFocusEffect: showsFocusEffect,
          isEnabled: isEnabled,
          styleEnvironment: styleEnvironment
        )
      }
    }
    .foregroundStyle(triggerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: triggerChrome.opacity))
    .layoutMetadata(
      .init(
        minimumHeight: 1 + 1 + (isActiveNavigation ? options.count : 0)
      )
    )
  }

  private func menuPickerOptionList(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let rowLineWidth = inlineRowIntrinsicLineWidth(for: options)
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<options.count) { index in
        pickerRow(
          label: options[index].label,
          isSelected: index == selectedIndex,
          isActiveNavigation: showsFocusEffect,
          isEnabled: isEnabled,
          styleEnvironment: styleEnvironment,
          lineWidth: rowLineWidth,
          routeIdentity: pickerOptionIdentity(
            for: controlIdentity,
            index: index
          )
        )
      }
    }
    .padding(.init(leading: 1))
  }

  @ViewBuilder
  private func inlinePickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> some View {
    let containerChrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    // Focus is communicated by the thick border overlay; avoid a tinted
    // container fill, which otherwise reads as every row being highlighted.
    let containerFillStyle = AnyShapeStyle(.background)
    let resolvedLineWidth = lineWidth ?? inlineRowIntrinsicLineWidth(for: options)
    let rows = inlineRows(
      controlIdentity: controlIdentity,
      options: options,
      selectedIndex: selectedIndex,
      isActiveNavigation: isActiveNavigation && showsFocusEffect,
      isEnabled: isEnabled,
      styleEnvironment: styleEnvironment,
      viewportLineCount: viewportLineCount,
      lineWidth: resolvedLineWidth
    )

    VStack(alignment: .leading, spacing: 0) {
      label
        .foregroundStyle(.terminalBorder(.accent))
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<rows.count) { index in
          inlineRowView(
            rows[index],
            controlIdentity: controlIdentity,
            isActiveNavigation: isActiveNavigation && showsFocusEffect,
            isEnabled: isEnabled,
            styleEnvironment: styleEnvironment,
            lineWidth: resolvedLineWidth
          )
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(containerFillStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
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

  /// Intrinsic row width used so every inline/menu option row occupies the
  /// same cell width — the selected-row highlight then covers the full row
  /// instead of wrapping to the label and leaving a jagged right edge.
  private func inlineRowIntrinsicLineWidth(for options: [Option]) -> Int {
    let maxLabelWidth =
      options
      .map { layoutText(for: $0.label, width: nil).size.width }
      .max() ?? 0
    // `controlFocusRail` reserves a single cell for the rail glyph and
    // `controlFocusRow` inserts one cell of spacing between rail and content.
    return maxLabelWidth + 2
  }

  private func inlineRows(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isActiveNavigation: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> [InlinePickerRow] {
    let indexedOptions = Array(options.enumerated())
    let rowOptions: ArraySlice<(offset: Int, element: Option)>
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

  private func pickerMarkerLine(
    _ text: String?,
    lineWidth: Int?
  ) -> some View {
    Text(text ?? "")
      .lineLimit(1)
      .foregroundStyle(.separator)
      .frame(width: lineWidth, alignment: .leading)
  }

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

  @ViewBuilder
  private func segmentedPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let containerChrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    VStack(alignment: .leading, spacing: 0) {
      label
        .foregroundStyle(.terminalBorder(.accent))
      HStack(alignment: .center, spacing: 1) {
        ForEach(0..<options.count) { index in
          segmentedSegmentView(
            option: options[index],
            index: index,
            controlIdentity: controlIdentity,
            selectedIndex: selectedIndex,
            isActiveNavigation: isActiveNavigation,
            showsFocusEffect: showsFocusEffect,
            isEnabled: isEnabled,
            styleEnvironment: styleEnvironment
          )
          if index < options.count - 1 {
            Divider()
          }
        }
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(containerChrome.backgroundStyle)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
        )
      }
    }
    .foregroundStyle(containerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: containerChrome.opacity))
  }

  private func segmentedSegmentView(
    option: Option,
    index: Int,
    controlIdentity: Identity,
    selectedIndex: Int?,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let isSelected = index == selectedIndex
    let segmentChrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isActiveNavigation && showsFocusEffect && isSelected,
      isSelected: isSelected
    )
    return Text(option.label)
      .lineLimit(1)
      .background {
        if isSelected {
          Rectangle().fill(.tint)
        } else if isActiveNavigation && showsFocusEffect {
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
          for: controlIdentity,
          index: index
        )
      )
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
  }

  @ViewBuilder
  private func radioGroupPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) -> some View {
    let containerChrome = styleEnvironment.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    VStack(alignment: .leading, spacing: 0) {
      label
        .foregroundStyle(.terminalBorder(.accent))
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<options.count) { index in
          radioGroupRow(
            label: options[index].label,
            isSelected: index == selectedIndex,
            isFocused: isActiveNavigation && showsFocusEffect && index == selectedIndex,
            isEnabled: isEnabled,
            styleEnvironment: styleEnvironment,
            routeIdentity: pickerOptionIdentity(
              for: controlIdentity,
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
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          containerChrome.borderStyle,
          style: isFocused && showsFocusEffect ? .thick : .init(),
          backgroundStyle: containerChrome.borderBackgroundStyle
        )
      }
    }
    .foregroundStyle(containerChrome.foregroundStyle)
    .drawMetadata(.init(opacity: containerChrome.opacity))
    .fixedSize(horizontal: false, vertical: true)
    .layoutMetadata(
      .init(
        minimumHeight: 1 + options.count + 2
      )
    )
  }

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
}
