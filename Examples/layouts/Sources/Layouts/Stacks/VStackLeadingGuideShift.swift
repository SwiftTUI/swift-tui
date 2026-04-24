import TerminalUI

/// A `VStack(alignment: .leading)` with four labelled rows, where the
/// middle row overrides its `.leading` alignment guide to shift
/// itself 4 cells to the right of the stack's default leading edge.
///
/// The remaining rows hug the stack's leading edge as normal,
/// producing a visible "notch" at the `shifted` row. The catalog
/// marker `"VStack leading guide shift"` is the first row so it also
/// hugs the leading edge and acts as a baseline reference.
public struct VStackLeadingGuideShift: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("VStack leading guide shift").foregroundStyle(.muted)
      Text("normal")
      Text("shifted").alignmentGuide(.leading) { _ in 4 }
      Text("normal again")
    }
    .padding(1)
  }
}
