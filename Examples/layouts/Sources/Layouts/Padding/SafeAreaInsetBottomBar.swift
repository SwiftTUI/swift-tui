import SwiftTUIRuntime

/// A scrolling content column with a status bar pinned to the bottom
/// via `.safeAreaInset(edge: .bottom)`. The inset reduces the inner
/// proposal so the content does not paint into the bar's row — the
/// content rows stop above the `[STATUS BAR]` row.
///
/// The header `"Safe area inset bottom bar"` is the catalog marker and
/// sits as the first row inside the `ScrollView` (so the `ScrollView`
/// still claims the full vertical space reduced by the safe-area
/// inset).
public struct SafeAreaInsetBottomBar: View {
  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Safe area inset bottom bar").foregroundStyle(.muted)
        ForEach(0..<30, id: \.self) { i in
          Text("content \(i)")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      Text("[STATUS BAR]")
        .foregroundStyle(.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
