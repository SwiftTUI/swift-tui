import SwiftTUIRuntime

/// Nine `Text` markers each claim the same outer 60×20 frame via
/// `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:)` at
/// one of the nine standard `Alignment` anchors. Rendering them in a
/// ZStack shows that the flexible-frame alignment dictates where the
/// content is positioned inside the maxed-out box.
///
/// Markers are two-character labels chosen to be unique across the grid:
///
/// ```
/// TL   TC   TR
/// LC   [C]  RC
/// BL   BC   BR
/// ```
///
/// The center marker is bracketed (`"[C]"`) so it cannot collide with
/// the letter `C` appearing inside any of the directional markers.
///
/// The header `"Flexible frame alignment grid"` is the catalog marker
/// and sits above the grid.
public struct FlexibleFrameAlignmentGrid: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Flexible frame alignment grid").foregroundStyle(.muted)
      ZStack {
        Text("TL").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Text("TC").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        Text("TR").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        Text("LC").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        Text("[C]").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        Text("RC").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        Text("BL").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        Text("BC").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        Text("BR").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
      .frame(width: 60, height: 20)
      .border(.separator)
    }
    .padding(1)
  }
}
