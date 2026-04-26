import SwiftUI

/// Behaviour-tier layout pinning that `.alert(_:isPresented:)` overlays
/// presentation chrome WITHOUT reflowing the underlying content. The
/// underlying view's first content cell stays at the same row/column
/// when the alert is hidden vs. shown.
///
/// Layout shape: a `VStack(alignment: .leading)` of:
///   1. a header marker `Text("Alert anchor stable")`,
///   2. a `Text("[FIRST CELL]")` whose row/column is the test anchor,
///   3. five rows of `Text("body row \(i)")`.
/// The whole stack is `.padding(1)`'d and carries
/// `.alert("Title", isPresented:)` whose actions builder returns a
/// trivial `Text("OK")` — the alert is bound to a `@State Bool` that
/// the smoke render leaves at `false`.
///
/// The behaviour test renders TWO sibling variants — one with the
/// alert hidden, one with the alert open — and asserts the column AND
/// row of `[FIRST CELL]` match across both rasters. That match is the
/// anchor-stable invariant: the alert's overlay does not reflow the
/// underlying content's layout.
public struct AlertAnchorStable: View {
  public init() {}

  @State private var isShowingAlert: Bool = false

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Alert anchor stable")
      Text("[FIRST CELL]")
      ForEach(0..<5, id: \.self) { i in
        Text("body row \(i)")
      }
    }
    .padding(1)
    .alert(
      "Title",
      isPresented: $isShowingAlert,
      actions: {
        Text("OK")
      },
      message: {
        EmptyView()
      }
    )
  }
}
