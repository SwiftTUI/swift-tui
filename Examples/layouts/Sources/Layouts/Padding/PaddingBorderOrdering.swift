import SwiftTUI

/// Two `Text("A")` views side-by-side that differ only in the order of
/// `.padding` vs `.border` modifiers. The left box applies padding
/// first (the border then wraps the padded content); the right box
/// applies border first (then padding pushes the whole bordered box
/// outward). The difference shows up in how much empty space sits
/// between the border ring and the letter `A`: the first box has a
/// visible 1-cell gap on each side, the second box has a border that
/// hugs the `A` tightly while the outer padding adds empty cells
/// outside the border ring.
///
/// The header `"Padding border ordering"` is the catalog marker.
public struct PaddingBorderOrdering: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Padding border ordering").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 4) {
        Text("A")
          .padding(1)
          .border(.separator)
        Text("A")
          .border(.separator)
          .padding(1)
      }
    }
    .padding(1)
  }
}
