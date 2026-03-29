import Core

extension Picker {
  func pickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    pickerStyle: PickerStyle,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> AnyView {
    switch pickerStyle {
    case .segmented:
      return segmentedPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        appearance: appearance
      )
    case .radioGroup:
      return radioGroupPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        appearance: appearance
      )
    case .menu:
      return menuPickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        appearance: appearance
      )
    case .inline, .automatic:
      return inlinePickerBody(
        controlIdentity: controlIdentity,
        options: options,
        selectedIndex: selectedIndex,
        isFocused: isFocused,
        isActiveNavigation: isActiveNavigation,
        showsFocusEffect: showsFocusEffect,
        isEnabled: isEnabled,
        appearance: appearance,
        viewportLineCount: viewportLineCount,
        lineWidth: lineWidth
      )
    }
  }

  private func menuPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance
  ) -> AnyView {
    let triggerChrome = appearance.rowChrome(
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

    let triggerRow = AnyView(
      HStack(alignment: .center, spacing: 1) {
        Text(selectedLabel)
          .lineLimit(1)
        Spacer()
        Text(isActiveNavigation ? "▴" : "▾")
      }
      .foregroundStyle(triggerChrome.foregroundStyle)
      .drawMetadata(.init(opacity: triggerChrome.opacity))
      .id(parallelPickerTriggerIdentity(for: controlIdentity))
      .semanticMetadata(.init(participatesInPointerHitTesting: true))
    )

    let content = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "PickerLabel")
            .foregroundStyle(.muted)
        }
        Group {
          if isFocused {
            triggerRow.background {
              Rectangle().fill(triggerChrome.backgroundStyle)
            }
          } else {
            triggerRow
          }
        }

        if isActiveNavigation {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<options.count) { index in
              pickerRow(
                label: options[index].label,
                isSelected: index == selectedIndex,
                isActiveNavigation: isActiveNavigation && showsFocusEffect,
                isEnabled: isEnabled,
                appearance: appearance,
                lineWidth: nil,
                routeIdentity: parallelPickerOptionIdentity(
                  for: controlIdentity,
                  index: index
                )
              )
            }
          }
          .padding(.init(leading: 2))
        }
      }
      .foregroundStyle(triggerChrome.foregroundStyle)
      .drawMetadata(.init(opacity: triggerChrome.opacity))
      .layoutMetadata(
        .init(
          minimumHeight: (labelViews.isEmpty ? 0 : 1) + 1 + (isActiveNavigation ? options.count : 0)
        )
      )
    )

    return content
  }

  private func inlinePickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> AnyView {
    let containerChrome = appearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let contentRows = inlineRows(
      controlIdentity: controlIdentity,
      options: options,
      selectedIndex: selectedIndex,
      isActiveNavigation: isActiveNavigation && showsFocusEffect,
      isEnabled: isEnabled,
      appearance: appearance,
      viewportLineCount: viewportLineCount,
      lineWidth: lineWidth
    )

    let content = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "PickerLabel")
            .foregroundStyle(.muted)
        }
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<contentRows.count) { index in
            contentRows[index]
          }
        }
        .padding(.init(all: 1))
        .background {
          RoundedRectangle(cornerRadius: 1).parallelInteriorFill(containerChrome.backgroundStyle)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(
            containerChrome.borderStyle,
            backgroundStyle: containerChrome.borderBackgroundStyle
          )
        }
      }
      .foregroundStyle(containerChrome.foregroundStyle)
      .drawMetadata(.init(opacity: containerChrome.opacity))
      .layoutMetadata(
        .init(
          minimumHeight: (labelViews.isEmpty ? 0 : 1) + contentRows.count + 2
        )
      )
    )

    return content
  }

  private func inlineRows(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isActiveNavigation: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance,
    viewportLineCount: Int?,
    lineWidth: Int?
  ) -> [AnyView] {
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
      topMarker = offset > 0 ? "^ more" : nil
      bottomMarker = end < options.count ? "v more" : nil
    } else {
      rowOptions = indexedOptions[indexedOptions.startIndex..<indexedOptions.endIndex]
      topMarker = nil
      bottomMarker = nil
    }

    var rows: [AnyView] = []

    if viewportLineCount != nil {
      rows.append(pickerMarkerLine(topMarker, lineWidth: lineWidth))
    }

    for option in rowOptions {
      rows.append(
        pickerRow(
          label: option.element.label,
          isSelected: option.offset == selectedIndex,
          isActiveNavigation: isActiveNavigation,
          isEnabled: isEnabled,
          appearance: appearance,
          lineWidth: lineWidth,
          routeIdentity: parallelPickerOptionIdentity(
            for: controlIdentity,
            index: option.offset
          )
        )
      )
    }

    if viewportLineCount != nil {
      rows.append(pickerMarkerLine(bottomMarker, lineWidth: lineWidth))
    }

    return rows
  }

  private func pickerMarkerLine(
    _ text: String?,
    lineWidth: Int?
  ) -> AnyView {
    AnyView(
      Text(text ?? "")
        .lineLimit(1)
        .foregroundStyle(.muted)
        .frame(width: lineWidth, alignment: .leading)
    )
  }

  private func pickerRow(
    label: String,
    isSelected: Bool,
    isActiveNavigation: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance,
    lineWidth: Int?,
    routeIdentity: Identity? = nil
  ) -> AnyView {
    let rowChrome = appearance.rowChrome(
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
    let row = HStack(alignment: .center, spacing: 0) {
      Text(isSelected ? "| " : "  ")
        .foregroundStyle(markerStyle)
      Text(label)
        .lineLimit(1)
        .foregroundStyle(labelStyle)
    }
    .drawMetadata(.init(opacity: rowChrome.opacity))
    .frame(width: lineWidth, alignment: .leading)

    let content = AnyView(
      Group {
        if isSelected && isActiveNavigation {
          row.background {
            Rectangle().fill(rowChrome.backgroundStyle)
          }
        } else {
          row
        }
      }
    )

    guard let routeIdentity else {
      return content
    }

    return AnyView(
      PointerRouteView(
        identity: routeIdentity,
        content: content
      )
    )
  }

  private func segmentedPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance
  ) -> AnyView {
    let containerChrome = appearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let content = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "PickerLabel")
            .foregroundStyle(.muted)
        }
        HStack(alignment: .center, spacing: 1) {
          ForEach(0..<options.count) { index in
            let option = options[index]
            let segmentChrome = appearance.controlChrome(
              isEnabled: isEnabled,
              isFocused: isActiveNavigation && showsFocusEffect && index == selectedIndex,
              isSelected: index == selectedIndex
            )
            let isSelected = index == selectedIndex
            Text(isSelected ? "[\(option.label)]" : option.label)
              .lineLimit(1)
              .padding(
                .init(
                  top: 0,
                  leading: isSelected && isActiveNavigation ? 1 : 0,
                  bottom: 0,
                  trailing: isSelected && isActiveNavigation ? 1 : 0
                )
              )
              .background {
                if isSelected && isActiveNavigation && showsFocusEffect {
                  RoundedRectangle(cornerRadius: 1).parallelInteriorFill(
                    segmentChrome.backgroundStyle
                  )
                }
              }
              .foregroundStyle(segmentChrome.foregroundStyle)
              .drawMetadata(.init(opacity: segmentChrome.opacity))
              .id(
                parallelPickerOptionIdentity(
                  for: controlIdentity,
                  index: index
                )
              )
              .semanticMetadata(.init(participatesInPointerHitTesting: true))
          }
        }
        .padding(.init(all: 1))
        .background {
          RoundedRectangle(cornerRadius: 1).parallelInteriorFill(containerChrome.backgroundStyle)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(
            containerChrome.borderStyle,
            backgroundStyle: containerChrome.borderBackgroundStyle
          )
        }
      }
      .foregroundStyle(containerChrome.foregroundStyle)
      .drawMetadata(.init(opacity: containerChrome.opacity))
    )

    return content
  }

  private func radioGroupPickerBody(
    controlIdentity: Identity,
    options: [Option],
    selectedIndex: Int?,
    isFocused: Bool,
    isActiveNavigation: Bool,
    showsFocusEffect: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance
  ) -> AnyView {
    let containerChrome = appearance.controlChrome(
      isEnabled: isEnabled,
      isFocused: isFocused && showsFocusEffect
    )

    let content = AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty {
          combinedView(from: labelViews, kindName: "PickerLabel")
            .foregroundStyle(.muted)
        }
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<options.count) { index in
            radioGroupRow(
              label: options[index].label,
              isSelected: index == selectedIndex,
              isFocused: isActiveNavigation && showsFocusEffect && index == selectedIndex,
              isEnabled: isEnabled,
              appearance: appearance,
              routeIdentity: parallelPickerOptionIdentity(
                for: controlIdentity,
                index: index
              )
            )
          }
        }
        .padding(.init(all: 1))
        .background {
          RoundedRectangle(cornerRadius: 1).parallelInteriorFill(containerChrome.backgroundStyle)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 1).parallelStrokeBorder(
            containerChrome.borderStyle,
            backgroundStyle: containerChrome.borderBackgroundStyle
          )
        }
      }
      .foregroundStyle(containerChrome.foregroundStyle)
      .drawMetadata(.init(opacity: containerChrome.opacity))
      .fixedSize(horizontal: false, vertical: true)
      .layoutMetadata(
        .init(
          minimumHeight: (labelViews.isEmpty ? 0 : 1) + options.count + 2
        )
      )
    )

    return content
  }

  private func radioGroupRow(
    label: String,
    isSelected: Bool,
    isFocused: Bool,
    isEnabled: Bool,
    appearance: TerminalAppearance,
    routeIdentity: Identity? = nil
  ) -> AnyView {
    let rowChrome = appearance.rowChrome(
      isEnabled: isEnabled,
      isFocused: isFocused,
      isSelected: isFocused
    )

    let content = AnyView(
      Group {
        let row = HStack(alignment: .center, spacing: 1) {
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

        if isSelected && isFocused {
          row.background {
            Rectangle().fill(rowChrome.backgroundStyle)
          }
        } else {
          row
        }
      }
    )

    guard let routeIdentity else {
      return content
    }

    return AnyView(
      PointerRouteView(
        identity: routeIdentity,
        content: content
      )
    )
  }
}
