import SwiftTUICore

// The menu picker style body.
//
// `MenuPickerStyleBody` renders a collapsed trigger row showing the current
// selection; when navigation is active it expands `MenuPickerOptionList`
// below it. Shared option-row rendering lives in `PickerSharedRendering.swift`.
//
// Split out of `PickerRendering.swift`, which was decomposed into one file per
// picker style.

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

    VStack(alignment: .leading, spacing: 0) {
      configuration.label
        .foregroundStyle(.terminalBorder(.accent))
      configuration.trigger { triggerRow }

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
        let option = configuration.options[index]
        option.route {
          pickerRow(
            label: option.label,
            isSelected: option.isSelected,
            isActiveNavigation: configuration.showsFocusEffect,
            isEnabled: option.isEnabled,
            styleEnvironment: configuration.styleEnvironment,
            lineWidth: rowLineWidth
          )
        }
      }
    }
    .padding(.init(leading: 1))
  }
}
