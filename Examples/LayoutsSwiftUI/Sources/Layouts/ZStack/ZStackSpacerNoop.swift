import SwiftUI

/// Pins the ZStack × Spacer interaction: a `Spacer` placed inside a
/// `ZStack` is layout-neutral — it does NOT claim all proposed space.
/// The ZStack therefore hugs the tightest non-Spacer child
/// (`Text("[X]")`, 3 cells wide) rather than stretching to the full
/// terminal width.
///
/// A `.border(Color.gray)` wraps the ZStack to make the measured
/// footprint visible: if the border hugs the three cells of `"[X]"`,
/// the Spacer was a no-op; if the border spans the full width, the
/// Spacer DID claim space (file finding).
///
/// The header `"ZStack spacer noop"` is the catalog marker.
public struct ZStackSpacerNoop: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("ZStack spacer noop").foregroundStyle(.secondary)
      ZStack {
        Spacer()
        Text("[X]")
      }
      .border(Color.gray)
    }
    .padding(cell(1))
  }
}
