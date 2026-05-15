import SwiftTUIRuntime

/// A horizontal `ScrollView` whose child is a row of `Text` views
/// each greedily sized via `.frame(maxWidth: .infinity)`. In a
/// horizontal scroll axis, `.infinity` must NOT be interpreted as
/// "take the proposed width" (there is no finite horizontal proposal
/// inside a horizontal ScrollView) or layout would hang / explode.
/// SwiftUI parity: the greedy children resolve to their natural
/// (content) widths and the HStack lays them out in sequence.
///
/// Layout shape: five `Text("item \(i)").frame(maxWidth: .infinity)`
/// cells in an `HStack(spacing: 1)`, wrapped in
/// `ScrollView(.horizontal)` constrained to `.frame(width: 20)` and
/// surrounded by `.border(.separator)` so the viewport is visible.
///
/// Observable invariants (see the behaviour test):
///   - Rendering completes (no hang / infinite loop).
///   - `item 0` is painted somewhere in the raster.
///   - The bordered viewport is exactly 20 cells wide — the
///     `ScrollView` takes its finite horizontal proposal and the
///     greedy children collapse to their intrinsic widths instead of
///     demanding infinite space.
///
/// The header `"Horizontal scroll with infinite child"` is the
/// catalog marker and sits above the bordered viewport.
public struct HorizontalScrollWithInfiniteChild: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Horizontal scroll with infinite child").foregroundStyle(.muted)
      ScrollView(.horizontal) {
        HStack(spacing: 1) {
          ForEach(0..<5, id: \.self) { i in
            Text("item \(i)").frame(maxWidth: .infinity)
          }
        }
      }
      .frame(width: 20)
      .border(.separator)
    }
    .padding(1)
  }
}
