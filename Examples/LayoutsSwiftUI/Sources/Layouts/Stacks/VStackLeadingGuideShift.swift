import SwiftUI

/// A `VStack(alignment: .leading)` with four labelled rows, where the
/// middle row overrides its `.leading` alignment guide to shift
/// itself 4 cells to the right of the stack's default leading edge.
///
/// The remaining rows hug the stack's leading edge as normal,
/// producing a visible "notch" at the `shifted` row. Row markers
/// (`"plain above"`, `"shifted"`, `"plain below"`) are unique words so
/// that behaviour tests can match any single row unambiguously via
/// substring matching.
///
/// The catalog marker `"VStack leading guide shift"` is the first row
/// so it also hugs the leading edge and acts as a baseline reference.
public struct VStackLeadingGuideShift: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("VStack leading guide shift").foregroundStyle(.secondary)
      Text("plain above")
      Text("shifted").alignmentGuide(.leading) { _ in 4 }
      Text("plain below")
    }
    .padding(1)
  }
}
