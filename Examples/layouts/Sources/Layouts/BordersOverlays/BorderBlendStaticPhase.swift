import SwiftTUI

/// Two bordered boxes side-by-side that share the same `BorderBlend`
/// palette but differ only in the static `phase` parameter:
///
///   - LEFT:  phase = 0.0 — the blend starts at its first color
///     (`.red`) at the top-left corner and walks clockwise around the
///     perimeter from there.
///   - RIGHT: phase = 0.5 — the blend is rotated by half a perimeter,
///     so the top-left corner now samples the blend at `t = 0.5`
///     (approximately the midpoint between `.green` and `.cyan`).
///
/// No animation is driven; the contrast is static. The header
/// `"Border blend static phase"` is the catalog marker.
public struct BorderBlendStaticPhase: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Border blend static phase").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 3) {
        VStack(alignment: .leading, spacing: 0) {
          Text("phase 0.0").foregroundStyle(.muted)
          Text("X")
            .padding(2)
            .border(
              blend: BorderBlend([.red, .yellow, .green, .cyan]),
              set: .rounded,
              phase: 0.0
            )
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("phase 0.5").foregroundStyle(.muted)
          Text("X")
            .padding(2)
            .border(
              blend: BorderBlend([.red, .yellow, .green, .cyan]),
              set: .rounded,
              phase: 0.5
            )
        }
      }
    }
    .padding(1)
  }
}
