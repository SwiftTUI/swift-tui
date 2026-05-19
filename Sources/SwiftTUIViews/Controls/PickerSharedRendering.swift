import SwiftTUICore

// Picker rendering helpers shared by more than one picker style.
//
// `inlineRowIntrinsicLineWidth` and `pickerRow` are used by both the menu and
// the inline picker styles, so they live here rather than in either style's
// file. Both are widened from `private` to file-internal to model that
// genuine cross-file sharing — `internal` (not `package`) because
// `pickerRow` takes an `internal` `StyleEnvironmentSnapshot` parameter.
//
// Split out of `PickerRendering.swift`, which was decomposed into one file per
// picker style.

/// Intrinsic row width used so every inline/menu option row occupies the
/// same cell width — the selected-row highlight then covers the full row
/// instead of wrapping to the label and leaving a jagged right edge.
@MainActor
func inlineRowIntrinsicLineWidth(
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
@ViewBuilder
func pickerRow(
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
