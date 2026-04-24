import TerminalUI

/// A bordered 20×5 box with a single-character badge (`●`) pinned to
/// the bottom-trailing corner via `.overlay(alignment: .bottomTrailing)`.
/// The overlay modifier's alignment parameter anchors the badge at the
/// chosen corner of the base view's frame; the test pins that the
/// badge appears at the BOTTOM-RIGHT of the box rather than floating
/// somewhere else.
///
/// The header `"Overlay alignment badge"` is the catalog marker.
public struct OverlayAlignmentBadge: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Overlay alignment badge").foregroundStyle(.muted)
      Text("box content")
        .frame(width: 20, height: 5)
        .border(set: .single)
        .overlay(alignment: .bottomTrailing) {
          Text("●").foregroundStyle(Color.red)
        }
    }
    .padding(1)
  }
}
