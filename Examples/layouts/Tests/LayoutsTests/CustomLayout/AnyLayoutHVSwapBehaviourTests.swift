import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape and child markers, but the
/// `AnyLayout` containers are replaced by plain `Group` content
/// (no layout policy at all).  Without a layout container the three
/// children resolve into the enclosing VStack and stack
/// vertically — proving that the HV-swap distinction in
/// ``AnyLayoutHVSwap`` comes from the erased `HStackLayout`, not
/// from incidental child stacking.
@MainActor
private struct AnyLayoutHVSwapFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Any layout HV swap").foregroundStyle(.muted)

      Text("VStackLayout").foregroundStyle(.muted)
      Group {
        Text("[A]")
        Text("[B]")
        Text("[C]")
      }
      .border(.separator)

      Text("HStackLayout").foregroundStyle(.muted)
      Group {
        Text("[A]")
        Text("[B]")
        Text("[C]")
      }
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct AnyLayoutHVSwapBehaviourTests {
  /// Pins the layout-policy distinction surfaced by `AnyLayout`.
  ///
  /// The first container erases a `VStackLayout`: its three `[A]`,
  /// `[B]`, `[C]` children must occupy three distinct rows.  The
  /// second container erases an `HStackLayout`: the same three
  /// children must collapse onto a single row.  Counting the rows
  /// that each marker occupies is enough to pin both halves.
  ///
  /// Observed raster (excerpt) at 80×30:
  ///
  /// ```
  /// Any layout HV swap
  /// VStackLayout
  /// ▛▀▀▀▜
  /// ▌[A]▐
  /// ▌[B]▐
  /// ▌[C]▐
  /// ▙▄▄▄▟
  /// HStackLayout
  /// ▛▀▀▀▀▀▀▀▀▀▜
  /// ▌[A] [B] [C]▐
  /// ▙▄▄▄▄▄▄▄▄▄▟
  /// ```
  ///
  /// In the VStackLayout container, each child marker appears on
  /// its own row.  In the HStackLayout container, all three child
  /// markers share the same row.  We assert there is exactly one
  /// row containing all three markers (the H container's row) and
  /// at least three rows containing one marker each (the V
  /// container's three rows).
  @Test("VStackLayout container stacks rows; HStackLayout container packs into one row")
  func swapPicksAxis() {
    let raster = render(AnyLayoutHVSwap(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // Rows that contain all three markers — only the HStackLayout
    // container should produce such a row.
    let allThreeRows = raster.lines.enumerated().filter {
      $0.element.contains("[A]") && $0.element.contains("[B]") && $0.element.contains("[C]")
    }
    #expect(
      allThreeRows.count == 1,
      """
      expected exactly one row containing all three markers (the \
      HStackLayout container's single row); got \(allThreeRows.count). \
      If this fails, AnyLayout's HStackLayout erasure is no longer \
      packing siblings horizontally.
      \(joined)
      """
    )

    // The VStackLayout container should put each marker on a
    // distinct row.  We expect at least one row per marker.
    let aRows = raster.rows(containing: "[A]")
    let bRows = raster.rows(containing: "[B]")
    let cRows = raster.rows(containing: "[C]")
    #expect(
      aRows.count >= 2 && bRows.count >= 2 && cRows.count >= 2,
      """
      expected each of `[A]`, `[B]`, `[C]` to appear on at least 2 \
      rows total (one in the V container, one in the H container's \
      packed row). Got A=\(aRows.count) B=\(bRows.count) \
      C=\(cRows.count). If this fails, the VStackLayout container \
      may have collapsed its children.
      \(joined)
      """
    )

    // The VStackLayout container places `[A]` strictly above `[B]`
    // strictly above `[C]` in distinct rows.  Use the FIRST
    // occurrence of each marker: the first occurrence of `[A]` is
    // the V container's first row; `[B]`'s first occurrence is
    // *also* in the V container (the H container is below the V
    // container in the source order, so its row appears later).
    if let firstA = aRows.first, let firstB = bRows.first, let firstC = cRows.first {
      #expect(
        firstA < firstB && firstB < firstC,
        """
        expected the VStackLayout container to put `[A]` strictly \
        above `[B]` strictly above `[C]`; got rows A=\(firstA) \
        B=\(firstB) C=\(firstC).
        \(joined)
        """
      )
      // And those three V-container rows must each contain only
      // their own marker (else the V container is also packing
      // horizontally).
      if let aLine = raster.row(at: firstA), let bLine = raster.row(at: firstB),
        let cLine = raster.row(at: firstC)
      {
        #expect(
          !aLine.contains("[B]") && !aLine.contains("[C]"),
          "VStack `[A]` row leaked into other markers: \(aLine)\n\(joined)"
        )
        #expect(
          !bLine.contains("[A]") && !bLine.contains("[C]"),
          "VStack `[B]` row leaked into other markers: \(bLine)\n\(joined)"
        )
        #expect(
          !cLine.contains("[A]") && !cLine.contains("[B]"),
          "VStack `[C]` row leaked into other markers: \(cLine)\n\(joined)"
        )
      }
    }
  }

  /// A/B vacuity: replacing each `AnyLayout(...)` with a plain
  /// `Group { ... }` removes the explicit layout-policy choice.
  /// Both containers then defer to the enclosing VStack's vertical
  /// stacking, so neither one collapses its children onto a single
  /// row.  The "all three markers on one row" invariant from
  /// ``swapPicksAxis`` therefore disappears.
  @Test("removing AnyLayout collapses both containers to vertical stacking")
  func anyLayoutIsNonVacuous() {
    let withSwap = render(
      AnyLayoutHVSwap(),
      width: 80,
      height: 30,
      id: "with-swap"
    ).rasterSurface
    let withoutSwap = render(
      AnyLayoutHVSwapFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-swap"
    ).rasterSurface

    let withDump = withSwap.lines.joined(separator: "\n")
    let withoutDump = withoutSwap.lines.joined(separator: "\n")

    let withAllThree = withSwap.lines.contains {
      $0.contains("[A]") && $0.contains("[B]") && $0.contains("[C]")
    }
    let withoutAllThree = withoutSwap.lines.contains {
      $0.contains("[A]") && $0.contains("[B]") && $0.contains("[C]")
    }
    #expect(
      withAllThree,
      "WITH-AnyLayout should have one row containing [A] [B] [C]\n\(withDump)"
    )
    #expect(
      !withoutAllThree,
      """
      WITHOUT-AnyLayout (Group fallback) should have NO row containing \
      all three markers — the enclosing VStack stacks them vertically.
      \(withoutDump)
      """
    )
  }
}
