import SwiftTUIRuntime

/// Two concentric borders built by alternating `.padding(1).border(...)`
/// twice: the inner `.border(.single)` hugs the content, a `.padding(1)`
/// gap opens radial space, then an outer `.border(.double)` wraps the
/// padded inner ring. The net layout is two rings with a one-cell gap
/// between them — the outer double ring is drawn with ASCII double-box
/// glyphs (`═ ║ ╔ ╗ ╚ ╝`) and the inner single ring uses single-box
/// glyphs (`─ │ ┌ ┐ └ ┘`).
///
/// The ordering matters: `.padding(1).border(.single).padding(1).border(.double)`
/// reads outside-in as
///   outer double → 1-cell padding → inner single → 1-cell padding → content.
///
/// The header `"Nested border ordering"` is the catalog marker.
public struct NestedBorderOrdering: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Nested border ordering").foregroundStyle(.muted)
      Text("X")
        .padding(1)
        .border(set: .single)
        .padding(1)
        .border(set: .double)
    }
    .padding(1)
  }
}
