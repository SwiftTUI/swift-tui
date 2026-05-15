import SwiftUI

/// Three HStacks of mixed-height children, one per `VerticalAlignment`
/// (`.top`, `.center`, `.bottom`). Pins where the shorter child
/// anchors within each row. The marker text `"triad"` appears
/// exactly once (in the header) so it identifies this layout in the
/// raster without colliding with children.
public struct HStackAlignmentTriad: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("HStack alignment triad").foregroundStyle(.secondary)
      row("top", alignment: .top)
      row("center", alignment: .center)
      row("bottom", alignment: .bottom)
    }
    .padding(cell(1))
  }

  private func row(_ label: String, alignment: VerticalAlignment) -> some View {
    HStack(alignment: alignment, spacing: cell(1)) {
      Text(label).frame(width: cell(7), alignment: .leading)
      Text("tall\ntall\ntall").border(Color.gray)
      Text("short").border(Color.gray)
    }
  }
}
