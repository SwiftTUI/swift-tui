import SwiftUI

/// Two concentric borders built by alternating `.padding(1).border(...)`
/// twice: the inner `.border(Color.gray)` hugs the content, a `.padding(1)`
/// gap opens radial space, then an outer `.border(Color.gray, width: 2)` wraps the
/// padded inner ring. The net layout is two rings with a one-cell gap
/// between them — the outer double ring is drawn with ASCII double-box
/// glyphs (`═ ║ ╔ ╗ ╚ ╝`) and the inner single ring uses single-box
/// glyphs (`─ │ ┌ ┐ └ ┘`).
///
/// The ordering matters: `.padding(1).border(Color.gray).padding(1).border(Color.gray, width: 2)`
/// reads outside-in as
///   outer double → 1-cell padding → inner single → 1-cell padding → content.
///
/// The header `"Nested border ordering"` is the catalog marker.
public struct NestedBorderOrdering: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: cell(1)) {
      Text("Nested border ordering").foregroundStyle(.secondary)
      Text("X")
        .padding(cell(1))
        .border(Color.gray)
        .padding(cell(1))
        .border(Color.gray, width: 2)
    }
    .padding(cell(1))
  }
}
