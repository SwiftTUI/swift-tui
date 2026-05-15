import SwiftUI

/// One big `ZStack` whose children each claim the full stack via
/// flexible frame and anchor at distinct `Alignment`s. The five
/// corner/center markers (`TL`, `TR`, `[C]`, `BL`, `BR`) pin that
/// `.topLeading`, `.topTrailing`, `.center`, `.bottomLeading`, and
/// `.bottomTrailing` route children to their expected quadrants.
///
/// The center marker is wrapped in brackets (`"[C]"`) so it cannot
/// collide with the letter `C` appearing inside any other label or
/// word when grepped by the behaviour test.
///
/// The header `"ZStack alignment grid"` is the catalog marker and
/// sits above the stack so it doesn't interfere with corner-anchor
/// assertions.
public struct ZStackAlignmentGrid: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("ZStack alignment grid").foregroundStyle(.secondary)
      ZStack {
        Text("TL").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Text("TR").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        Text("[C]").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        Text("BL").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        Text("BR").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}
