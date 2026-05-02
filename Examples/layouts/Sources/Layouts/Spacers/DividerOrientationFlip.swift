import SwiftTUI

/// Pins the orientation flip on `Divider`: a divider draws a
/// HORIZONTAL rule when nested in a `VStack`, and a VERTICAL rule
/// when nested in an `HStack` — the SwiftUI parity behaviour.
///
/// Layout shape: two side-by-side panels in an outer `HStack`.
///   - Left panel: `VStack { Text("V-1"); Divider(); Text("V-2") }`
///     → divider draws a horizontal rule (`─`) BETWEEN the two rows.
///   - Right panel: `HStack { Text("H-1"); Divider(); Text("H-2") }`
///     → divider draws a vertical rule (`│`) BETWEEN the two cells
///     on a single row.
///
/// The header `"Divider orientation flip"` is the catalog marker.
public struct DividerOrientationFlip: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Divider orientation flip").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 4) {
        VStack(alignment: .leading, spacing: 0) {
          Text("V-1")
          Divider()
          Text("V-2")
        }
        HStack(spacing: 0) {
          Text("H-1")
          Divider()
          Text("H-2")
        }
      }
    }
  }
}
