import SwiftUI

/// A single `.frame(minWidth: 20, idealWidth: 40, maxWidth: 60)` view
/// shown under three parent proposals:
///
/// - Below min (`.frame(width: 10)`) — the inner view clamps UP to 20.
/// - At ideal (`.frame(width: 40)`) — the inner view sits at 40.
/// - Above max (`.frame(width: 80)`) — the inner view clamps DOWN to 60.
///
/// The `.border` around the clamped view makes its measured width
/// visible to the behaviour test.
///
/// The header `"Min ideal max frame clamp"` is the catalog marker.
public struct MinIdealMaxFrameClamp: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Min ideal max frame clamp").foregroundStyle(.secondary)
      clampedBox.frame(width: 10)
      clampedBox.frame(width: 40)
      clampedBox.frame(width: 80)
    }
    .padding(1)
  }

  private var clampedBox: some View {
    Text("clamped")
      .frame(
        minWidth: 20,
        idealWidth: 40,
        maxWidth: 60,
        minHeight: 3,
        alignment: .center
      )
      .border(Color.gray)
  }
}
