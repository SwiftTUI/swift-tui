import TerminalUI

/// Pins that a vertical `ScrollView` takes its proposed height and
/// measures its content against that viewport: content taller than
/// the viewport overflows (gets scrolled), and the `ScrollView`
/// itself claims exactly the proposed height — it does NOT grow to
/// fit its content.
///
/// Layout shape: a 30-row `VStack` of `Text("row \(i)")` children is
/// placed inside a `ScrollView` that is constrained to
/// `.frame(height: 8)`. A single-line `.border(.separator)` wraps the
/// frame so the bordered region is exactly 8 rows tall — the
/// behaviour test reads the border rows to pin the viewport height.
///
/// Observable invariants (see the behaviour test):
///   - `row 0` paints inside the viewport (first content row visible).
///   - `row 29` does NOT appear anywhere in the raster (proves the
///     content overflowed the 8-row viewport).
///   - The bordered region is exactly 8 rows tall (proves the
///     `ScrollView` took the `.frame(height: 8)` proposal).
///
/// The header `"Vertical scroll measures content"` is the catalog
/// marker and sits above the bordered viewport.
public struct VerticalScrollMeasuresContent: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Vertical scroll measures content").foregroundStyle(.muted)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { i in
            Text("row \(i)")
          }
        }
      }
      .frame(height: 8)
      .border(.separator)
    }
    .padding(1)
  }
}
