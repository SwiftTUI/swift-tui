import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PickerShellTests {
  @Test("Picker rasterises with one section per represented Category")
  func pickerShowsAllCategories() {
    // Each List row in the picker is 2 lines (title + blurb), plus a
    // section header per Category. With 56 layouts across 16 categories
    // that is ~128 rows of body content; rasterise into a viewport
    // tall enough to host them all so the scrolled-off sections still
    // appear in the surface.
    let raster = render(
      LayoutPicker(onSelect: { _ in }),
      width: 80,
      height: 200,
      id: "picker-shell"
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")
    for category in LayoutEntry.Category.allCases {
      #expect(
        joined.contains(category.rawValue),
        "picker did not show category section '\(category.rawValue)'"
      )
    }
    #expect(
      joined.contains("56 layouts"),
      "picker header did not show 56-layout count"
    )
  }
}
