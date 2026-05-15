import SwiftTUIRuntime

/// Demonstrates that `.ignoresSafeArea(.bottom)` reclaims space an
/// outer `.safeAreaPadding(.bottom, N)` reserved from the ambient
/// safe-area environment.
///
/// The shape:
///   - The outer `.safeAreaPadding(.bottom, 3)` establishes a 3-row
///     ambient bottom safe area that the ScrollView would otherwise
///     stop short of.
///   - The inner `.ignoresSafeArea(.bottom)` on the ScrollView
///     reclaims that 3-row zone, so content rows paint all the way
///     to the bottom of the viewport.
///
/// The header `"Ignores safe area bleed"` is the catalog marker and
/// sits as the first row of the scrolling content so the marker is
/// visible in the rendered raster.
///
/// The observable A/B contrast (see the behaviour test):
///   - WITH `.ignoresSafeArea(.bottom)`: content extends to the last
///     row of the viewport.
///   - WITHOUT `.ignoresSafeArea(.bottom)`: content stops 3 rows
///     higher, leaving the safe-area zone empty.
public struct IgnoresSafeAreaBleed: View {
  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Ignores safe area bleed").foregroundStyle(.muted)
        ForEach(0..<30, id: \.self) { i in
          Text("content \(i)")
        }
      }
    }
    .ignoresSafeArea(.bottom)
    .safeAreaPadding(.bottom, 3)
  }
}
