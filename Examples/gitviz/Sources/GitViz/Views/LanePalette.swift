import SwiftTUI

/// Per-lane colors used by `DagCommand` to make individual branches
/// visually traceable through merge fan-outs and convergences.
///
/// Lane 0 keeps the default foreground (most repos have a single "main"
/// line that's busiest); subsequent lanes cycle through the four
/// accented semantic styles so even repositories with a deep history of
/// concurrent branches stay readable. The renderer falls back to `.muted`
/// for glyphs that don't belong to any specific lane (e.g., inter-lane
/// spaces in a commit row).
enum LanePalette {
  static func style(for lane: Int?) -> AnyShapeStyle {
    guard let lane else {
      return AnyShapeStyle(.muted)
    }
    let palette: [AnyShapeStyle] = [
      AnyShapeStyle(.foreground),
      AnyShapeStyle(.info),
      AnyShapeStyle(.success),
      AnyShapeStyle(.warning),
      AnyShapeStyle(.danger),
    ]
    return palette[lane % palette.count]
  }
}
