import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Rendered-view tests for the custom `Layout` container contract (plan
/// 2026-08-31-001): the declared orientation reaching `Spacer`/`Divider`,
/// built-in parity for `HStackLayout {}` vs `HStack {}`, the `AnyLayout`
/// orientation switch, and spacing/alignment answers surviving the composed
/// pipeline — including the frame-tail worker.
@MainActor
@Suite("Custom layout container contract — rendered (plan 2026-08-31-001)")
struct CustomLayoutContainerContractRenderTests {
  @Test("a declared horizontal orientation gives Spacer and Divider the row axis")
  func declaredOrientationReachesChildren() {
    let artifacts = DefaultRenderer().render(
      VStack {
        RibbonLayout {
          Text("A")
          Spacer(minLength: 2)
          Divider()
          Text("B")
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    let ribbon = artifacts.resolvedTree.children[0]
    #expect(ribbon.kind == .view("RibbonLayout"))
    #expect(ribbon.children.count == 4)
    let spacer = ribbon.children[1]
    let divider = ribbon.children[2]
    #expect(spacer.drawMetadata.leafStackAxis == .horizontal)
    #expect(spacer.intrinsicSize == .init(width: 2, height: 0))
    #expect(divider.drawMetadata.leafStackAxis == .horizontal)
  }

  @Test("a layout without a declared orientation clears the enclosing stack's axis")
  func undeclaredOrientationClearsInheritedAxis() {
    let artifacts = DefaultRenderer().render(
      VStack {
        PlainLayout {
          Spacer(minLength: 2)
        }
        Spacer(minLength: 2)
      },
      context: .init(identity: testIdentity("Root"))
    )

    let inLayout = artifacts.resolvedTree.children[0].children[0]
    let inStack = artifacts.resolvedTree.children[1]
    // Inside the non-stack layout a spacer is flexible on both axes, as in
    // a ZStack; the sibling directly in the VStack keeps the column axis.
    #expect(inLayout.drawMetadata.leafStackAxis == nil)
    #expect(inLayout.intrinsicSize == .init(width: 2, height: 2))
    #expect(inStack.drawMetadata.leafStackAxis == .vertical)
    #expect(inStack.intrinsicSize == .init(width: 0, height: 2))
  }

  @Test("ZStack {} clears the enclosing stack's axis exactly like ZStackLayout {}")
  func zStackClearsInheritedAxisLikeZStackLayout() {
    // Built-in parity (org T11): the ZStack view and the ZStackLayout
    // container must hand their children the same axis — none. Before the
    // fix a Spacer inside `VStack { ZStack { … } }` kept the column axis and
    // reserved its minimum on one axis only; inside `HStack { ZStack { … } }`
    // the row axis. Measured against SwiftUI (macOS 15 SDK): a ZStack is
    // "not a stack" for both `Spacer` and `Divider`.
    let artifacts = DefaultRenderer().render(
      VStack {
        HStack {
          ZStack {
            Spacer(minLength: 2)
          }
          ZStackLayout {
            Spacer(minLength: 2)
          }
          Spacer(minLength: 2)
        }
        ZStack {
          Spacer(minLength: 2)
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    let row = artifacts.resolvedTree.children[0]
    let inZStackUnderRow = row.children[0].children[0]
    let inZStackLayoutUnderRow = row.children[1].children[0]
    let inRow = row.children[2]
    let inZStackUnderColumn = artifacts.resolvedTree.children[1].children[0]

    #expect(inZStackUnderRow.drawMetadata.leafStackAxis == nil)
    #expect(inZStackUnderRow.intrinsicSize == .init(width: 2, height: 2))
    #expect(inZStackLayoutUnderRow.drawMetadata.leafStackAxis == nil)
    #expect(inZStackLayoutUnderRow.intrinsicSize == .init(width: 2, height: 2))
    #expect(inZStackUnderColumn.drawMetadata.leafStackAxis == nil)
    #expect(inZStackUnderColumn.intrinsicSize == .init(width: 2, height: 2))
    // The row's own spacer keeps the row axis: the clearing is scoped to
    // the ZStack's children, not leaked to its siblings.
    #expect(inRow.drawMetadata.leafStackAxis == .horizontal)
    #expect(inRow.intrinsicSize == .init(width: 2, height: 0))
  }

  @Test("a Spacer beside siblings stays layout-neutral in a ZStack under either stack")
  func zStackSpacerBesideSiblingsStaysLayoutNeutral() throws {
    // SwiftUI ignores a Spacer for sizing when a ZStack has other children
    // (probe: `ZStack { Spacer(); Text("[X]") }` answers the text's size under
    // an 800×100 proposal, nested in a VStack or an HStack). The axis change
    // must not disturb that: the bordered ZStack still hugs `[X]`.
    for nestInRow in [false, true] {
      let probe: AnyView =
        nestInRow
        ? AnyView(
          HStack(alignment: .top, spacing: 0) {
            Text("h")
            ZStack { Spacer(); Text("[X]") }.border(.separator, placement: .outset)
          })
        : AnyView(
          VStack(alignment: .leading, spacing: 0) {
            Text("h")
            ZStack { Spacer(); Text("[X]") }.border(.separator, placement: .outset)
          })
      let surface = DefaultRenderer().render(
        probe,
        context: .init(identity: testIdentity("Root", nestInRow ? "row" : "column")),
        proposal: .init(width: 40, height: 8)
      ).rasterSurface
      let joined = surface.lines.joined(separator: "\n")
      let boxLine = try #require(surface.lines.first { $0.contains("[X]") }, "\(joined)")
      // `│[X]│` — the outset border hugs the three text cells.
      #expect(boxLine.contains("│[X]│"), "\(joined)")
      let borderedRows = surface.lines.filter { $0.contains("│") || $0.contains("╭") || $0.contains("╰") }
      #expect(borderedRows.count == 3, "\(joined)")
    }
  }

  @Test("HStackLayout {} and HStack {} give a Spacer the same axis")
  func builtinLayoutParityForSpacer() {
    let viaLayout = DefaultRenderer().render(
      VStack {
        HStackLayout {
          Text("A")
          Spacer()
          Text("B")
        }
      },
      context: .init(identity: testIdentity("ViaLayout")),
      proposal: .init(width: 8, height: 1)
    )
    let viaStack = DefaultRenderer().render(
      VStack {
        HStack {
          Text("A")
          Spacer()
          Text("B")
        }
      },
      context: .init(identity: testIdentity("ViaStack")),
      proposal: .init(width: 8, height: 1)
    )

    #expect(viaStack.rasterSurface.lines == ["A      B"])
    #expect(viaLayout.rasterSurface.lines == viaStack.rasterSurface.lines)
  }

  @Test("switching an AnyLayout between stack layouts flips the spacer's axis")
  func anyLayoutSwitchFlipsSpacerAxis() {
    let horizontal = AnyLayout(HStackLayout())
    let vertical = AnyLayout(VStackLayout())

    let row = DefaultRenderer().render(
      horizontal {
        Text("A")
        Spacer()
        Text("B")
      },
      context: .init(identity: testIdentity("Row")),
      proposal: .init(width: 4, height: 3)
    )
    let column = DefaultRenderer().render(
      vertical {
        Text("A")
        Spacer()
        Text("B")
      },
      context: .init(identity: testIdentity("Column")),
      proposal: .init(width: 4, height: 3)
    )

    // The same erased value installs the axis its layout declares.
    let rowSpacer = row.resolvedTree.children[1]
    let columnSpacer = column.resolvedTree.children[1]
    #expect(rowSpacer.kind == .view("Spacer"))
    #expect(rowSpacer.drawMetadata.leafStackAxis == .horizontal)
    #expect(columnSpacer.drawMetadata.leafStackAxis == .vertical)
    // The surface is the proposal's size; the row fills its first line and
    // the column fills its first and last.
    #expect(row.rasterSurface.lines.first == "A  B")
    #expect(column.rasterSurface.lines.count == 3)
    #expect(column.rasterSurface.lines.first == "A")
    #expect(column.rasterSurface.lines.last == "B")
  }

  @Test("a declared spacing opens a gap in the parent stack's render")
  func declaredSpacingRenders() {
    let spaced = DefaultRenderer().render(
      VStack {
        Text("A")
        SpacedLayout {
          Text("B")
        }
      },
      context: .init(identity: testIdentity("Spaced"))
    )
    let plain = DefaultRenderer().render(
      VStack {
        Text("A")
        PlainLayout {
          Text("B")
        }
      },
      context: .init(identity: testIdentity("Plain"))
    )

    #expect(plain.rasterSurface.lines == ["A", "B"])
    #expect(spaced.rasterSurface.lines.count == 3)
    #expect(spaced.rasterSurface.lines.first == "A")
    #expect(spaced.rasterSurface.lines.last == "B")
  }

  @Test("an explicit leading answer aligns the container inside a VStack")
  func explicitLeadingAnswerRenders() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading) {
        Text("ABCDEF")
        LeadingGuideLayout {
          Text("xy")
        }
      },
      context: .init(identity: testIdentity("Root"))
    )

    // The container says its leading edge sits three cells in, so the
    // sibling's leading edge is aligned three cells to the right of the
    // container's origin.
    #expect(artifacts.measuredTree.measuredSize.width == 9)
    #expect(artifacts.placedTree.children.map(\.bounds.origin.x) == [3, 0])
    #expect(artifacts.rasterSurface.lines.first == "   ABCDEF")
    #expect(artifacts.rasterSurface.lines.last?.hasPrefix("xy") == true)
  }

  @Test("container hooks run with layout on the frame-tail worker")
  func hooksRunOnFrameTailWorker() async throws {
    let artifacts = await DefaultRenderer().renderAsync(
      VStack(alignment: .leading) {
        Text("ABCDEF")
        LeadingGuideLayout {
          Text("xy")
        }
      },
      context: .init(identity: testIdentity("AsyncContractRoot")),
      proposal: .init(width: 12, height: 4)
    )

    let workerTimings = try #require(artifacts.diagnostics.timing.workerTimings)
    #expect(artifacts.diagnostics.work.customLayoutFallbackCount == 0)
    #expect(artifacts.diagnostics.work.firstCustomLayoutFallbackIdentity == nil)
    #expect(workerTimings.layoutCompute != .zero)
    #expect(artifacts.placedTree.children.map(\.bounds.origin.x) == [3, 0])
    #expect(artifacts.rasterSurface.lines.first?.hasPrefix("   ABCDEF") == true)
  }
}

// MARK: - Fixture layouts

/// Lays subviews out in a row and declares the row axis.
private struct RibbonLayout: Layout {
  static var layoutProperties: LayoutProperties {
    LayoutProperties(stackOrientation: .horizontal)
  }

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return .init(
      width: sizes.reduce(0) { $0 + $1.width },
      height: sizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    var x = bounds.origin.x
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        proposal: .init(width: size.width, height: size.height)
      )
      x += size.width
    }
  }
}

/// Sizes to its first subview and declares nothing.
private struct PlainLayout: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    for subview in subviews {
      subview.place(
        at: bounds.origin,
        proposal: .init(width: bounds.size.width, height: bounds.size.height)
      )
    }
  }
}

/// `PlainLayout` that asks its parent for one row of vertical spacing.
private struct SpacedLayout: Layout {
  func spacing(subviews _: LayoutSubviews, cache _: inout Void) -> ViewSpacing {
    ViewSpacing(vertical: 1)
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    PlainLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    PlainLayout().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}

/// `PlainLayout` that reports its leading guide three cells in.
private struct LeadingGuideLayout: Layout {
  func explicitAlignment(
    of guide: HorizontalAlignment,
    in _: LayoutRect,
    proposal _: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> Int? {
    guide == .leading ? 3 : nil
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    PlainLayout().sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache: inout Void
  ) {
    PlainLayout().placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
  }
}
