import SwiftTUI

/// A four-row form whose `label:value` rows all share a single
/// colon column, regardless of label length, by right-aligning the
/// `label:` text inside a fixed-width column.
///
/// Approach: each row is `HStack(spacing: 0) { Text("label:")
/// .frame(width: 8, alignment: .trailing); Text(" value") }`. The
/// fixed-width trailing-aligned frame pushes every `:` to the same
/// raster column irrespective of the label's intrinsic width. The
/// outer `VStack(alignment: .leading)` then aligns rows by their
/// leading edge (column 0 of each row's frame), so the colon
/// columns coincide.
///
/// Why not the alignment-guide path? `.alignmentGuide(.leading) {
/// d in d.width }` (anchor leading guide at the right edge of the
/// first child) would express the colon column directly, but the
/// resulting child-shift direction is opposite the naive intuition
/// — see `docs/proposals/layout/BEHAVIOUR_FINDINGS.md` Finding #1.
/// The right-aligned-frame approach is faithful to SwiftUI's
/// "Aligning views across stacks" form-layout idiom and is easier
/// to read at a glance, so this layout uses that shape and the
/// dimension-dependent guide variant lives in
/// ``AlignmentGuideDimensionDependent`` (#47).
///
/// The catalog marker `"Colon aligned form"` is the first row so it
/// also acts as a header.
public struct ColonAlignedForm: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Colon aligned form").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        row(label: "name", value: "Alice")
        row(label: "email", value: "alice@example.com")
        row(label: "color", value: "blue")
        row(label: "x", value: "42")
      }
      .border(.separator)
    }
    .padding(1)
  }

  private func row(label: String, value: String) -> some View {
    HStack(spacing: 0) {
      Text("\(label):").frame(width: 8, alignment: .trailing)
      Text(" \(value)")
    }
  }
}
