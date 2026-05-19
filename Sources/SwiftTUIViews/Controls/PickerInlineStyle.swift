import SwiftTUICore

// The inline picker style body.
//
// `InlinePickerStyleBody` renders every option as a row inside a bordered
// container, scrolling a window of rows (with `↑`/`↓` markers) when the option
// count exceeds the viewport. `InlinePickerRow` is the per-row model;
// `inlineRows` builds the windowed row list; `inlineRowView` and
// `pickerMarkerLine` render a row. Shared option-row rendering lives in
// `PickerSharedRendering.swift`.
//
// Split out of `PickerRendering.swift`, which was decomposed into one file per
// picker style. `InlinePickerRow` and the three helpers are used only here, so
// they stay `private`.

private enum InlinePickerRow {
  case marker(String?)
  case option(index: Int, label: String, isSelected: Bool)
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
