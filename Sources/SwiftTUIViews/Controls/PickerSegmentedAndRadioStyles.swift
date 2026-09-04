import SwiftTUICore

// The segmented and radio-group picker style bodies.
//
// `SegmentedPickerStyleBody` lays options out horizontally as adjacent
// segments; `RadioGroupPickerStyleBody` stacks them as `(*)`/`( )` rows. Each
// has its own exclusively-used `private` renderer (`segmentedSegmentView`,
// `radioGroupRow`).
//
// Renamed from `PickerRendering.swift`, which was decomposed into one file per
// picker style — see also `PickerMenuStyle.swift`, `PickerInlineStyle.swift`,
// and `PickerSharedRendering.swift`.

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
          let option = configuration.options[index]
          option.route {
            radioGroupRow(
              label: option.label,
              isSelected: option.isSelected,
              isFocused: configuration.isActiveNavigation
                && configuration.showsFocusEffect
                && option.isSelected,
              isEnabled: option.isEnabled,
              styleEnvironment: configuration.styleEnvironment
            )
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
    .fixedSize(horizontal: false, vertical: true)
    .layoutMetadata(
      .init(
        minimumHeight: 1 + configuration.options.count + 2
      )
    )
  }
}

@MainActor
private func segmentedSegmentView(
  option: PickerStyleConfiguration.Option,
  configuration: PickerStyleConfiguration
) -> some View {
  let isSelected = option.isSelected
  let segmentChrome = configuration.styleEnvironment.controlChrome(
    isEnabled: configuration.isEnabled,
    isFocused: configuration.isActiveNavigation && configuration.showsFocusEffect && isSelected,
    isSelected: isSelected
  )
  return option.route {
    Text(option.label)
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
  }
}

@MainActor
@ViewBuilder
private func radioGroupRow(
  label: String,
  isSelected: Bool,
  isFocused: Bool,
  isEnabled: Bool,
  styleEnvironment: StyleEnvironmentSnapshot
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

  row
}
