import SwiftUI

/// A `GeometryReader` wrapped in `.frame(width: 40, height: 10)`.  The
/// proxy renders its observed `width` and `height` so the behaviour
/// test can pin the values reported by the reader.
///
/// SwiftUI semantics call for the `.frame` to TIGHTEN the proposal
/// reaching the GeometryReader so `proxy.size` reports `(40, 10)`.
///
/// The header `"Geometry reader takes proposal"` is the catalog marker.
public struct GeometryReaderTakesProposal: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader takes proposal").foregroundStyle(.secondary)
      GeometryReader { proxy in
        Text("w=\(proxy.size.width) h=\(proxy.size.height)")
      }
      .frame(width: 40, height: 10)
      .border(Color.gray)
    }
    .padding(1)
  }
}
