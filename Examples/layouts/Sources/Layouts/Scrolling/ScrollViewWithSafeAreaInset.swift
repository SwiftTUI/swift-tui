import TerminalUI

/// Pins the interaction between a vertical `ScrollView` and
/// `.safeAreaInset(edge: .top)`: the inset is pinned to the top edge
/// of the `ScrollView`'s viewport and the scrolling content's first
/// row starts BELOW the inset (the inset reduces the inner proposal).
///
/// Layout shape: a 30-row `VStack` of `Text("entry \(i)")` children
/// is placed inside a `ScrollView` with a `[TOP BAR]` inset attached
/// at `.top`, constrained to `.frame(height: 10)` and wrapped in
/// `.border(.separator)` so the viewport edges are visible.
///
/// Observable invariants (see the behaviour test):
///   - `[TOP BAR]` paints at the first content row of the viewport.
///   - `entry 0` paints at a strictly LATER row than the bar — the
///     inset reserves its row and the content flows beneath it.
///   - A/B comparison: without `.safeAreaInset`, `entry 0` starts
///     strictly higher than it does in the WITH variant (the bar's
///     row becomes available for content).
///
/// The header `"Scroll view with safe area inset"` is the catalog
/// marker and sits above the bordered viewport.
public struct ScrollViewWithSafeAreaInset: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll view with safe area inset").foregroundStyle(.muted)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { i in
            Text("entry \(i)")
          }
        }
      }
      .safeAreaInset(edge: .top) {
        Text("[TOP BAR]")
          .foregroundStyle(.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 10)
      .border(.separator)
    }
    .padding(1)
  }
}
