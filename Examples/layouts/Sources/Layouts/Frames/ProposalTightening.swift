import SwiftTUIRuntime

/// A `GeometryReader` wrapped in a `.frame(width: 30, height: 3)`. The
/// outer terminal width is much larger (≥ 60), but the fixed frame
/// should TIGHTEN the proposal that reaches the GeometryReader to 30.
///
/// The proxy renders its observed width as `"w=NN"` so the behaviour
/// test can pin the value reported by the GeometryReader. If the
/// proposal is correctly tightened by the surrounding `.frame`, the
/// raster will contain `"w=30"`. If the GeometryReader instead sees
/// the full terminal width, it would report something like `"w=80"`.
///
/// The header `"Proposal tightening"` is the catalog marker.
public struct ProposalTightening: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Proposal tightening").foregroundStyle(.muted)
      Text("outside geometry reader").foregroundStyle(.muted)
      GeometryReader { proxy in
        Text("w=\(proxy.size.width)")
      }
      .frame(width: 30, height: 3)
      .border(.separator)
    }
    .padding(1)
  }
}
