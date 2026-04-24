import TerminalUI

/// Mirrors the `SafeAreaInsetBottomBar` layout but the scrolling
/// content declares `.ignoresSafeArea(.bottom)` so it paints THROUGH
/// the bottom safe-area zone. The `[STATUS BAR]` overlays the bottom
/// row of the `ZStack` while content rows extend into the same row
/// underneath it.
///
/// The header `"Ignores safe area bleed"` is the catalog marker and
/// sits as the first row of the scrolling content so both the header
/// and content rows participate in the bleed.
public struct IgnoresSafeAreaBleed: View {
  public init() {}

  public var body: some View {
    ZStack(alignment: .bottom) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Ignores safe area bleed").foregroundStyle(.muted)
          ForEach(0..<30, id: \.self) { i in
            Text("content \(i)")
          }
        }
      }
      .ignoresSafeArea(.bottom)

      Text("[STATUS BAR]")
        .foregroundStyle(.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
