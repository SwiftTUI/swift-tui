import SwiftUI

/// Two copies of the same `Text("intrinsic content")`. The first is
/// rendered plain; the second is wrapped in a `.frame(width: 0,
/// height: 0)` to test how the library responds to a zero proposal
/// reaching an intrinsic-sized text.
///
/// Whether the zero-proposal copy renders, vanishes, or overflows is
/// pinned by the behaviour test.
///
/// The header `"Intrinsic text under zero proposal"` is the catalog
/// marker.
public struct IntrinsicTextUnderZeroProposal: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Intrinsic text under zero proposal").foregroundStyle(.secondary)
      Text("plain copy:").foregroundStyle(.secondary)
      Text("intrinsic content")
      Text("zero-frame copy:").foregroundStyle(.secondary)
      Text("intrinsic content").frame(width: 0, height: 0)
    }
    .padding(1)
  }
}
