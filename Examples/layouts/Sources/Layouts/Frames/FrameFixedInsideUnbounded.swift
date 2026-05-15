import SwiftTUIRuntime

/// Demonstrates that a fixed `.frame(width: 30, height: 5)` behaves the
/// same whether it sits inside a "tight" HStack (where a sibling and a
/// trailing `Spacer()` pull and push at its edges) or inside an
/// "unbounded" VStack that only gives it a trailing `Spacer()`.
///
/// Pinning the same visible box in both contexts shows that the
/// fixed-size frame does not change its dimensions based on the
/// surrounding stack's layout behaviour. Only the position of the
/// box within its row/column is dictated by the siblings.
///
/// The header `"Frame fixed inside unbounded"` is the catalog marker
/// and appears exactly once at the top of the layout.
public struct FrameFixedInsideUnbounded: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Frame fixed inside unbounded").foregroundStyle(.muted)
      Text("inside a tight HStack:").foregroundStyle(.muted)
      HStack(spacing: 1) {
        Text("label").foregroundStyle(.muted)
        fixedBox
        Spacer()
      }
      Text("inside an unbounded VStack:").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        fixedBox
        Spacer()
      }
    }
    .padding(1)
  }

  private var fixedBox: some View {
    Text("fixed 30x5")
      .frame(width: 30, height: 5, alignment: .center)
      .border(.separator)
  }
}
