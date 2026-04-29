import SwiftUI

/// A single bordered box with each of the four sides painted a
/// different color.
///
/// SwiftUI port: the original used TerminalUI's
/// `BorderEdgeStyle(top:right:bottom:left:)` plus a `.heavy` border
/// set — neither has a one-liner SwiftUI equivalent. This port
/// reaches the divergence by stacking four `.overlay` rectangles, one
/// per edge. Layout shape is intentionally preserved; readers of
/// BEHAVIOUR_FINDINGS comparing rasters should expect SwiftUI to
/// paint thin colored strokes rather than `━ ┃ ┏ ┓ ┗ ┛` glyphs.
public struct PerSideBorderColors: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Per-side border colors").foregroundStyle(.secondary)
      Text("X")
        .padding(2)
        .overlay(alignment: .top) {
          Rectangle().fill(Color.red).frame(height: 2)
        }
        .overlay(alignment: .trailing) {
          Rectangle().fill(Color.yellow).frame(width: 2)
        }
        .overlay(alignment: .bottom) {
          Rectangle().fill(Color.green).frame(height: 2)
        }
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.blue).frame(width: 2)
        }
    }
    .padding(1)
  }
}
