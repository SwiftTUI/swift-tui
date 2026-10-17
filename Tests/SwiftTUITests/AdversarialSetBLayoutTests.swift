// Adversarial set B: stack and frame layout minima, flexibility, and alignment.
//
// Motivated by the Sept-Oct 2026 reports on wrapped and fixed-size Spacers (STUI-613,
// 14ba359a), oversized aligned content (STUI-591), outset wide-glyph borders (STUI-595),
// decoration minimums (STUI-505), anchored custom placement (STUI-509, STUI-62), and nested
// toolbars that underfill their stacks. Every test asserts the SwiftUI contract, so a failure
// here is a finding about the engine, not a test to relax.
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: layout minima")
struct AdversarialSetBLayoutTests {
  // Equal division of a surplus hands remainder cells out symmetrically: one extra cell among
  // three equal flexibles belongs to the middle child, one among two to the trailing child.
  @Test func setB011OddSurplusAmongEqualFlexibleFramesIsPlacedSymmetrically() {
    let row = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("a").frame(maxWidth: .infinity)
        Text("b").frame(maxWidth: .infinity)
        Text("c").frame(maxWidth: .infinity)
      },
      context: .init(identity: testIdentity("SetBLayout", "setB011-row")),
      proposal: .init(width: 10, height: 1)
    )
    let rowWidths = row.placedTree.children.map { $0.bounds.size.width }
    #expect(rowWidths == [3, 4, 3], "row widths \(rowWidths)")
    #expect(row.rasterSurface.lines == [" a  b   c"], "row lines \(row.rasterSurface.lines)")

    let column = DefaultRenderer().render(
      VStack(spacing: 0) {
        Text("a").frame(maxHeight: .infinity)
        Text("b").frame(maxHeight: .infinity)
        Text("c").frame(maxHeight: .infinity)
      },
      context: .init(identity: testIdentity("SetBLayout", "setB011-column")),
      proposal: .init(width: 1, height: 7)
    )
    let columnHeights = column.placedTree.children.map { $0.bounds.size.height }
    #expect(columnHeights == [2, 3, 2], "column heights \(columnHeights)")
    #expect(
      column.rasterSurface.lines == ["a", "", "", "b", "", "c", ""],
      "column lines \(column.rasterSurface.lines)")

    let pair = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("a").frame(maxWidth: .infinity)
        Text("b").frame(maxWidth: .infinity)
      },
      context: .init(identity: testIdentity("SetBLayout", "setB011-pair")),
      proposal: .init(width: 7, height: 1)
    )
    let pairWidths = pair.placedTree.children.map { $0.bounds.size.width }
    #expect(pairWidths == [3, 4], "pair widths \(pairWidths)")
  }

  // `.fixedSize()` rigidifies only the view it wraps. A flexible frame around a fixed Spacer
  // still absorbs the row's surplus; a fixed frame around a flexible one does not.
  @Test func setB012FixedSizeSpacerInsideFlexibleFrameStillFillsTheRow() {
    let inside = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: 2).fixedSize().frame(maxWidth: .infinity)
        Text("R")
      },
      context: .init(identity: testIdentity("SetBLayout", "setB012-inside")),
      proposal: .init(width: 12, height: 1)
    )
    let insideWidths = inside.placedTree.children.map { $0.bounds.size.width }
    #expect(insideWidths == [1, 10, 1], "inside widths \(insideWidths)")
    let filled = "L" + String(repeating: " ", count: 10) + "R"
    #expect(inside.rasterSurface.lines == [filled], "inside lines \(inside.rasterSurface.lines)")

    let outside = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("L")
        Spacer(minLength: 2).frame(maxWidth: .infinity).fixedSize()
        Text("R")
      },
      context: .init(identity: testIdentity("SetBLayout", "setB012-outside")),
      proposal: .init(width: 12, height: 1)
    )
    let outsideWidths = outside.placedTree.children.map { $0.bounds.size.width }
    #expect(outsideWidths == [1, 2, 1], "outside widths \(outsideWidths)")
    #expect(outside.placedTree.bounds.size.width == 4, "\(outside.placedTree.bounds)")
    #expect(outside.rasterSurface.lines == ["L  R"], "outside lines \(outside.rasterSurface.lines)")
  }

  // Declared Spacer minima on both axes survive a proposal that cannot hold them, and the
  // trailing child is centered within the stack's resolved (not proposed) cross size.
  @Test func setB013NestedSpacerMinimaSurviveAnImpossibleTwoAxisDeficit() {
    let artifacts = DefaultRenderer().render(
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Text("A")
          Spacer(minLength: 3)
          Text("B")
        }
        Spacer(minLength: 2)
        Text("C")
      },
      context: .init(identity: testIdentity("SetBLayout", "setB013")),
      proposal: .init(width: 4, height: 3)
    )
    withKnownIssue("a nested HStack loses its Spacer minimum and drops its trailing child") {
      #expect(
        artifacts.measuredTree.measuredSize == CellSize(width: 5, height: 4),
        "\(artifacts.measuredTree.measuredSize)")
      #expect(artifacts.rasterSurface.size == CellSize(width: 5, height: 4))
      #expect(
        artifacts.rasterSurface.lines == ["A   B", "", "", "  C"],
        "\(artifacts.rasterSurface.lines)")
      let rowWidth = artifacts.placedTree.children.first?.bounds.size.width
      #expect(rowWidth == 5, "row width \(String(describing: rowWidth))")
    }
  }

  // A zero proposal clamps intrinsic leaves to nothing, but a declared Spacer minimum and a
  // `.fixedSize()` ideal are structural and must survive it on either stack axis.
  @Test func setB014ZeroProposalKeepsSpacerMinimaAndFixedSizeIdeals() {
    let row = DefaultRenderer().render(
      HStack(spacing: 0) {
        Spacer(minLength: 2)
        Text("X").fixedSize()
      },
      context: .init(identity: testIdentity("SetBLayout", "setB014-row")),
      proposal: .init(width: 0, height: 0)
    )
    #expect(
      row.measuredTree.measuredSize == CellSize(width: 3, height: 1),
      "row \(row.measuredTree.measuredSize)")
    #expect(row.rasterSurface.lines == ["  X"], "row lines \(row.rasterSurface.lines)")

    let column = DefaultRenderer().render(
      VStack(spacing: 0) {
        Spacer(minLength: 2)
        Text("X").fixedSize()
      },
      context: .init(identity: testIdentity("SetBLayout", "setB014-column")),
      proposal: .init(width: 0, height: 0)
    )
    #expect(
      column.measuredTree.measuredSize == CellSize(width: 1, height: 3),
      "column \(column.measuredTree.measuredSize)")
    #expect(
      column.rasterSurface.lines == ["", "", "X"], "column lines \(column.rasterSurface.lines)")
  }

  // Content larger than its frame on both axes overflows around every alignment, with the odd
  // cell always falling on the trailing and bottom side, and `.clipped()` shows the window the
  // alignment selects.
  @Test func setB015OversizedContentOverflowsAroundEveryFrameAlignment() {
    let expectations: [(alignment: Alignment, x: Int, y: Int)] = [
      (.topLeading, 0, 0), (.top, -1, 0), (.topTrailing, -2, 0),
      (.leading, 0, -1), (.center, -1, -1), (.trailing, -2, -1),
      (.bottomLeading, 0, -2), (.bottom, -1, -2), (.bottomTrailing, -2, -2),
    ]
    for (index, expectation) in expectations.enumerated() {
      let artifacts = DefaultRenderer().render(
        SetBOversizedBlock().frame(width: 4, height: 1, alignment: expectation.alignment),
        context: .init(identity: testIdentity("SetBLayout", "setB015-\(index)"))
      )
      #expect(
        artifacts.measuredTree.measuredSize == CellSize(width: 4, height: 1),
        "alignment \(index): \(artifacts.measuredTree.measuredSize)")
      let origin = artifacts.placedTree.children.first?.bounds.origin
      #expect(
        origin == CellPoint(x: expectation.x, y: expectation.y),
        "alignment \(index): \(String(describing: origin))")
    }

    let clipped = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("|")
        SetBOversizedBlock().frame(width: 4, height: 1, alignment: .bottomTrailing).clipped()
        Text("|")
      },
      context: .init(identity: testIdentity("SetBLayout", "setB015-clipped"))
    )
    withKnownIssue(".clipped() re-centers trailing-aligned overflow") {
      #expect(clipped.rasterSurface.lines == ["|3   |"], "clipped \(clipped.rasterSurface.lines)")
    }
  }

  // Overlays and backgrounds are size-neutral: a wider decoration overflows its primary
  // around the requested alignment and never raises the ideal or minimum of an enclosing
  // stack, even when that stack is squeezed below the decoration's width.
  @Test func setB016WiderDecorationsNeverRaiseAStackMinimum() throws {
    let overlayExpectations: [(alignment: Alignment, x: Int)] = [
      (.leading, 0), (.center, -3), (.trailing, -6),
    ]
    for (index, expectation) in overlayExpectations.enumerated() {
      let artifacts = DefaultRenderer().render(
        Text("abcd").overlay(alignment: expectation.alignment) {
          Text("ABCDEFGHIJ").fixedSize()
        },
        context: .init(identity: testIdentity("SetBLayout", "setB016-overlay-\(index)"))
      )
      #expect(
        artifacts.measuredTree.measuredSize == CellSize(width: 4, height: 1),
        "overlay \(index): \(artifacts.measuredTree.measuredSize)")
      let children = artifacts.placedTree.children
      #expect(children.count == 2, "overlay \(index): \(children.count) children")
      let origin = children.last?.bounds.origin
      #expect(
        origin == CellPoint(x: expectation.x, y: 0),
        "overlay \(index): \(String(describing: origin))")
    }

    let proposals: [ProposedSize] = [.init(width: 2, height: 2), .unspecified]
    for (index, proposal) in proposals.enumerated() {
      let overlaid = DefaultRenderer().render(
        VStack(spacing: 0) {
          Text("ab").overlay { Text("WIDE-OVERLAY").fixedSize() }
          Text("cd")
        },
        context: .init(identity: testIdentity("SetBLayout", "setB016-stack-overlay-\(index)")),
        proposal: proposal
      )
      #expect(
        overlaid.measuredTree.measuredSize == CellSize(width: 2, height: 2),
        "overlaid \(proposal): \(overlaid.measuredTree.measuredSize)")
      #expect(
        overlaid.placedTree.bounds.size == CellSize(width: 2, height: 2),
        "overlaid bounds \(proposal): \(overlaid.placedTree.bounds.size)")
      let decoration = try #require(overlaid.placedTree.children.first)
      #expect(decoration.children.count == 2, "overlaid \(proposal): \(decoration.children.count)")
      let overlayOrigin = decoration.children.last?.bounds.origin
      #expect(
        overlayOrigin == CellPoint(x: -5, y: 0),
        "overlaid \(proposal): \(String(describing: overlayOrigin))")

      let backed = DefaultRenderer().render(
        VStack(spacing: 0) {
          Text("ab").background { Text("WIDE-OVERLAY").fixedSize() }
          Text("cd")
        },
        context: .init(identity: testIdentity("SetBLayout", "setB016-stack-background-\(index)")),
        proposal: proposal
      )
      #expect(
        backed.measuredTree.measuredSize == CellSize(width: 2, height: 2),
        "backed \(proposal): \(backed.measuredTree.measuredSize)")
      let backedDecoration = try #require(backed.placedTree.children.first)
      let backgroundOrigins = backedDecoration.children.map { $0.bounds.origin.x }.sorted()
      #expect(backgroundOrigins == [-5, 0], "backed \(proposal): \(backgroundOrigins)")
    }
  }

  // STUI-595 reserved one row per wide horizontal outset edge. The same rule on the other axis
  // says a wide vertical edge glyph must reserve its full cell width, and padding plus partial
  // sides must not change the reservation arithmetic.
  @Test func setB017OutsetBordersReserveTheFullExtentOfWideEdgeGlyphs() {
    var horizontal = BorderSet.single
    horizontal.top = "界"
    horizontal.bottom = "界"
    let topAndLeading = DefaultRenderer().render(
      Text("hi")
        .padding(.horizontal, 1)
        .border(
          style: StrokeStyle(borderSet: horizontal), placement: .outset,
          sides: [.top, .leading]),
      context: .init(identity: testIdentity("SetBLayout", "setB017-horizontal"))
    )
    #expect(
      topAndLeading.measuredTree.measuredSize == CellSize(width: 5, height: 2),
      "horizontal \(topAndLeading.measuredTree.measuredSize)")
    let paddedOrigin = topAndLeading.placedTree.children.first?.bounds.origin
    #expect(
      paddedOrigin == CellPoint(x: 1, y: 1), "horizontal \(String(describing: paddedOrigin))")
    let horizontalLines = topAndLeading.rasterSurface.lines
    #expect(horizontalLines.count == 2, "horizontal \(horizontalLines)")
    #expect(horizontalLines.last == "│ hi", "horizontal \(horizontalLines)")
    let occluded = topAndLeading.diagnostics.runtime.issues.contains {
      $0.code == "layout.insetBorderOccludesContent"
    }
    #expect(!occluded)

    var vertical = BorderSet.single
    vertical.left = "界"
    let leadingOnly = DefaultRenderer().render(
      Text("hi").border(
        style: StrokeStyle(borderSet: vertical), placement: .outset, sides: .leading),
      context: .init(identity: testIdentity("SetBLayout", "setB017-vertical"))
    )
    #expect(
      leadingOnly.measuredTree.measuredSize == CellSize(width: 4, height: 1),
      "vertical \(leadingOnly.measuredTree.measuredSize)")
    let textOrigin = leadingOnly.placedTree.children.first?.bounds.origin
    #expect(textOrigin == CellPoint(x: 2, y: 0), "vertical \(String(describing: textOrigin))")
    let verticalLines = leadingOnly.rasterSurface.lines
    #expect(verticalLines.count == 1, "vertical \(verticalLines)")
    withKnownIssue("a wide glyph on a vertical outset edge reserves width but paints blanks") {
      #expect(verticalLines.first?.hasPrefix("界") == true, "vertical \(verticalLines)")
    }
    #expect(verticalLines.first?.hasSuffix("hi") == true, "vertical \(verticalLines)")
    #expect(leadingOnly.rasterSurface.size.width == 4, "vertical \(leadingOnly.rasterSurface.size)")
  }

  // `LayoutSubview.place(at:anchor:)` lands the child's *resolved* guide on the anchor point:
  // a public `.alignmentGuide` override moves the child, and a padding wrapper between the
  // guide and the layout propagates the override by its inset.
  @Test func setB018AnchoredCustomPlacementHonorsPublicAlignmentGuideOverrides() {
    let baseline = DefaultRenderer().render(
      SetBTrailingAnchorLayout { Text("AB") },
      context: .init(identity: testIdentity("SetBLayout", "setB018-baseline"))
    )
    let baselineOrigin = baseline.placedTree.children.first?.bounds.origin
    #expect(
      baselineOrigin == CellPoint(x: 6, y: 0), "baseline \(String(describing: baselineOrigin))")
    let sixSpaces = String(repeating: " ", count: 6) + "AB"
    #expect(baseline.rasterSurface.lines == [sixSpaces], "baseline \(baseline.rasterSurface.lines)")

    let overridden = DefaultRenderer().render(
      SetBTrailingAnchorLayout {
        Text("AB").alignmentGuide(.trailing) { dimensions in dimensions[.trailing] + 2 }
      },
      context: .init(identity: testIdentity("SetBLayout", "setB018-override"))
    )
    let overriddenOrigin = overridden.placedTree.children.first?.bounds.origin
    #expect(
      overriddenOrigin == CellPoint(x: 4, y: 0),
      "override \(String(describing: overriddenOrigin))")
    let fourSpaces = String(repeating: " ", count: 4) + "AB"
    #expect(
      overridden.rasterSurface.lines == [fourSpaces], "override \(overridden.rasterSurface.lines)")

    let padded = DefaultRenderer().render(
      SetBTrailingAnchorLayout {
        Text("AB")
          .alignmentGuide(.trailing) { dimensions in dimensions[.trailing] + 2 }
          .padding(.leading, 1)
      },
      context: .init(identity: testIdentity("SetBLayout", "setB018-padded"))
    )
    let paddedBounds = padded.placedTree.children.first?.bounds
    #expect(
      paddedBounds == CellRect(origin: CellPoint(x: 3, y: 0), size: CellSize(width: 3, height: 1)),
      "padded \(String(describing: paddedBounds))")
    #expect(padded.rasterSurface.lines == [fourSpaces], "padded \(padded.rasterSurface.lines)")
  }

  // A nested panel that hosts a bottom toolbar is flexible on both axes, so inside an HStack
  // it must take the row's surplus width and the full proposed height, pinning its strip to
  // the last row.
  @Test func setB019NestedBottomToolbarFillsItsHStackSurplus() {
    let frame = DefaultRenderer().render(
      HStack(spacing: 0) {
        Text("Side")
        Panel(id: "nested") {
          Text("Content").toolbarItem(
            .init(
              title: "Save", icon: nil, position: .bottom,
              isEnabled: true, action: {}))
        }.toolbar().toolbarStyle(DefaultBottomToolbarStyle())
      },
      context: .init(identity: testIdentity("SetBLayout", "setB019")),
      proposal: .init(width: 24, height: 6)
    )
    let lines = frame.rasterSurface.lines
    #expect(lines.count == 6, "\(lines)")
    #expect(lines.last?.contains("Save") == true, "\(lines)")
    #expect(frame.measuredTree.measuredSize == CellSize(width: 24, height: 6))
    let panelBounds = frame.placedTree.children.last?.bounds
    #expect(
      panelBounds
        == CellRect(origin: CellPoint(x: 4, y: 0), size: CellSize(width: 20, height: 6)),
      "panel \(String(describing: panelBounds))")
  }

  // The 14ba359a shape without TextField or List: a bordered row whose only flexible child is
  // a Spacer sits above a wider sibling. Cross reconciliation may stretch the row to the
  // sibling's width, but its declared minimum (5 + 2 + 2 + 2 = 11) must not become 12.
  @Test func setB020BorderedWrappedSpacerRowKeepsItsDeclaredMinimum() {
    let dashes = String(repeating: "─", count: 10)
    let expected = [
      "┌" + dashes + "┐",
      "│ Title    │",
      "└" + dashes + "┘",
      "123456789012",
    ]
    let proposals: [ProposedSize] = [.init(width: 12, height: 4), .unspecified]
    for (index, proposal) in proposals.enumerated() {
      let artifacts = DefaultRenderer().render(
        SetBBorderedRow(),
        context: .init(identity: testIdentity("SetBLayout", "setB020-\(index)")),
        proposal: proposal
      )
      #expect(
        artifacts.measuredTree.measuredSize == CellSize(width: 12, height: 4),
        "\(proposal): \(artifacts.measuredTree.measuredSize)")
      #expect(
        artifacts.rasterSurface.lines == expected, "\(proposal): \(artifacts.rasterSurface.lines)")
    }

    let narrow = DefaultRenderer().render(
      SetBBorderedRow(),
      context: .init(identity: testIdentity("SetBLayout", "setB020-narrow")),
      proposal: .init(width: 11, height: 4)
    )
    #expect(
      narrow.measuredTree.measuredSize.width == 11, "narrow \(narrow.measuredTree.measuredSize)")
    let rowWidth = narrow.placedTree.children.first?.bounds.size.width
    #expect(rowWidth == 11, "narrow row width \(String(describing: rowWidth))")
    let narrowLines = narrow.rasterSurface.lines
    #expect(narrowLines.count >= 2, "narrow \(narrowLines)")
    let narrowTop = "┌" + String(repeating: "─", count: 9) + "┐"
    #expect(narrowLines.first == narrowTop, "narrow \(narrowLines)")
    #expect(narrowLines.dropFirst().first == "│ Title   │", "narrow \(narrowLines)")
  }
}

/// A 6x3 block (`"ABCDEF"` over centered `"2"` and `"3"`) that is larger than a 4x1 frame on
/// both axes.
private struct SetBOversizedBlock: View {
  var body: some View {
    VStack(spacing: 0) {
      Text("ABCDEF")
      Text("2")
      Text("3")
    }
    .fixedSize()
  }
}

/// A bordered Spacer-bearing row above a wider sibling.
private struct SetBBorderedRow: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text("Title")
        Spacer(minLength: 2)
      }
      .padding(.horizontal, 1)
      .border(style: .single, placement: .outset)
      Text("123456789012")
    }
  }
}

/// An 8x1 layout that anchors its only subview's trailing guide to its own trailing edge.
private struct SetBTrailingAnchorLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    LayoutSize(width: 8, height: 1)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let subview = subviews.first else {
      return
    }
    subview.place(
      at: LayoutPoint(x: bounds.maxX, y: bounds.origin.y),
      anchor: .topTrailing,
      proposal: .unspecified
    )
  }
}
