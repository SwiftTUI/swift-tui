import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Raster edge cases where a fast path and the general path can disagree: a
// wide glyph or format character at a clip edge (the Sept–Oct 2026 reports
// behind 6d7de727 and 22ab77bb), ForeignSurface commits that leave a stale
// cell (F167, STUI-616), retained extraction serving a stale overlay border
// mask, degenerate shape and gradient inputs (STUI-501, the radial support
// walk) and zero-opacity content (STUI-592).
@MainActor
@Suite("Adversarial set B: raster edges")
struct AdversarialSetBRasterTests {
  @Test func setB041WideGlyphAtClipLastColumnIsDroppedButSurfaceEdgeKeepsLead() {
    for painter in SetBTextPainter.allCases {
      // An explicit clip needs the whole glyph: a wide glyph whose lead sits
      // in the clip's last column is dropped and leaves both cells untouched.
      let textBounds = CellRect(origin: .zero, size: .init(width: 5, height: 1))
      let clipped = DrawNode(
        identity: testIdentity("SetBRaster", "041-clip"), bounds: textBounds,
        clipBounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
        commands: [painter.command(bounds: textBounds, line: "abc漢")])
      let clippedSurface = Rasterizer().rasterize(
        clipped, minimumSize: .init(width: 5, height: 1))
      let clippedLines = clippedSurface.lines
      #expect(clippedLines == ["abc"], "\(painter): \(clippedLines)")
      #expect(clippedSurface.cells[0][3] == .empty, "\(painter)")
      #expect(clippedSurface.cells[0][4] == .empty, "\(painter)")

      // The surface edge only needs the lead cell: the glyph is written with
      // its full span and the terminal clips the continuation.
      let edge = DrawNode(
        identity: testIdentity("SetBRaster", "041-edge"),
        bounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
        commands: [painter.command(bounds: textBounds, line: "abc漢")])
      let edgeSurface = Rasterizer().rasterize(edge, minimumSize: .init(width: 4, height: 1))
      let edgeLines = edgeSurface.lines
      #expect(edgeSurface.size == CellSize(width: 4, height: 1), "\(painter)")
      #expect(edgeLines == ["abc漢"], "\(painter): \(edgeLines)")
      let lead = edgeSurface.cells[0][3]
      #expect(lead.character == "漢", "\(painter): \(lead)")
      #expect(lead.spanWidth == 2, "\(painter): \(lead)")
      #expect(lead.continuationLeadX == nil, "\(painter): \(lead)")
    }
  }

  @Test func setB042WideGlyphStraddlingClipLeftEdgeLeavesUnderlayIntact() {
    let size = CellSize(width: 5, height: 1)
    let surfaceBounds = CellRect(origin: .zero, size: size)
    for painter in SetBTextPainter.allCases {
      var root = DrawNode(
        identity: testIdentity("SetBRaster", "042-underlay"), bounds: surfaceBounds,
        commands: [setBUnderlayCommand(bounds: surfaceBounds)])
      let underlay = Rasterizer().rasterize(root, minimumSize: size)
      #expect(underlay.lines == ["ABCDE"], "\(painter)")

      // 漢 occupies columns 1-2 and the clip starts at column 2: the glyph is
      // rejected as a whole, so column 2 keeps the underlay's styled "C".
      root.children = [
        DrawNode(
          identity: testIdentity("SetBRaster", "042-straddle"), bounds: surfaceBounds,
          clipBounds: .init(origin: .init(x: 2, y: 0), size: .init(width: 3, height: 1)),
          commands: [painter.command(bounds: surfaceBounds, line: "x漢yz")])
      ]
      let surface = Rasterizer().rasterize(root, minimumSize: size)
      let lines = surface.lines
      #expect(lines == ["ABCyz"], "\(painter): \(lines)")
      let kept = Array(surface.cells[0][0..<3])
      let expected = Array(underlay.cells[0][0..<3])
      #expect(kept == expected, "\(painter): \(kept)")
      #expect(surface.cells[0][2].style == underlay.cells[0][2].style, "\(painter)")
      #expect(surface.cells[0][3].character == "y", "\(painter)")
      #expect(surface.cells[0][4].character == "z", "\(painter)")
    }
  }

  @Test func setB043ForeignSurfaceBlendAndFastPathAgreeOnClippedContinuation() {
    let size = CellSize(width: 5, height: 1)
    let surfaceBounds = CellRect(origin: .zero, size: size)
    let foreignBounds = CellRect(origin: .zero, size: .init(width: 3, height: 1))
    // The grid is well formed: a wide lead at column 1 and its continuation at
    // column 2, in the exact shape the rasterizer itself produces.
    let payload = SetBStaticPayload(
      grid: ForeignGrid(
        size: foreignBounds.size,
        cells: [
          [
            RasterCell(character: "x"),
            RasterCell(character: "寿", spanWidth: 2),
            RasterCell(character: " ", spanWidth: 0, continuationLeadX: 1),
          ]
        ]))
    let clip = CellRect(origin: .init(x: 2, y: 0), size: .init(width: 1, height: 1))
    let effects: [DrawEffects] = [.init(), .init([.blendMode(.normal)])]
    for drawEffects in effects {
      var root = DrawNode(
        identity: testIdentity("SetBRaster", "043-underlay"), bounds: surfaceBounds,
        commands: [setBUnderlayCommand(bounds: surfaceBounds)])
      let underlay = Rasterizer().rasterize(root, minimumSize: size)
      root.children = [
        DrawNode(
          identity: testIdentity("SetBRaster", "043-foreign"), bounds: foreignBounds,
          clipBounds: clip, drawEffects: drawEffects,
          commands: [.foreignSurface(bounds: foreignBounds, payload: payload)])
      ]
      let surface = Rasterizer().rasterize(root, minimumSize: size)
      let effectNames = drawEffects.ordered

      // Cells outside the clip are the underlay's.
      #expect(surface.cells[0][0] == underlay.cells[0][0], "\(effectNames)")
      #expect(surface.cells[0][1] == underlay.cells[0][1], "\(effectNames)")
      #expect(surface.cells[0][3] == underlay.cells[0][3], "\(effectNames)")
      #expect(surface.cells[0][4] == underlay.cells[0][4], "\(effectNames)")

      // The one cell inside the clip belongs to the foreign surface. Its lead
      // is clipped away, so the surface owns a blank there: neither leg may
      // leave the underlay's "C" showing through, and no orphan may remain.
      let claimed = surface.cells[0][2]
      do {
        #expect(claimed.character == " ", "\(effectNames): \(claimed)")
      }
      #expect(claimed.spanWidth == 1, "\(effectNames): \(claimed)")
      #expect(claimed.continuationLeadX == nil, "\(effectNames): \(claimed)")
    }
  }

  @Test func setB044LeadingCombiningMarkAndClippedZWJSequenceNeverShiftText() {
    // A lone combining mark at the start of a string is its own grapheme of
    // width zero. It must neither shift the text nor leave a bare mark cell.
    let markBounds = CellRect(origin: .zero, size: .init(width: 3, height: 1))
    let mark = DrawNode(
      identity: testIdentity("SetBRaster", "044-mark"), bounds: markBounds,
      commands: [SetBTextPainter.plain.command(bounds: markBounds, line: "\u{0301}ab")])
    let markSurface = Rasterizer().rasterize(mark, minimumSize: markBounds.size)
    let markLines = markSurface.lines
    #expect(markLines == ["ab"], "\(markLines)")
    #expect(markSurface.cells[0][0].character == "a")
    #expect(markSurface.cells[0][0].spanWidth == 1)
    #expect(markSurface.cells[0][1].character == "b")
    #expect(markSurface.cells[0][2] == .empty)

    // A ZWJ family sequence is one two-cell grapheme. Cut by a clip it is
    // dropped whole; unclipped it keeps its lead and continuation.
    let family = "a👨\u{200D}👩\u{200D}👧b"
    #expect(family.count == 3)
    let familyBounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))
    for painter in SetBTextPainter.allCases {
      let clipped = DrawNode(
        identity: testIdentity("SetBRaster", "044-zwj-clip"), bounds: familyBounds,
        clipBounds: .init(origin: .zero, size: .init(width: 2, height: 1)),
        commands: [painter.command(bounds: familyBounds, line: family)])
      let clippedSurface = Rasterizer().rasterize(clipped, minimumSize: familyBounds.size)
      let clippedLines = clippedSurface.lines
      #expect(clippedLines == ["a"], "\(painter): \(clippedLines)")
      #expect(clippedSurface.cells[0][1] == .empty, "\(painter)")
      #expect(clippedSurface.cells[0][2] == .empty, "\(painter)")
      #expect(clippedSurface.cells[0][3] == .empty, "\(painter)")

      let open = DrawNode(
        identity: testIdentity("SetBRaster", "044-zwj-open"), bounds: familyBounds,
        commands: [painter.command(bounds: familyBounds, line: family)])
      let openSurface = Rasterizer().rasterize(open, minimumSize: familyBounds.size)
      let openLines = openSurface.lines
      #expect(openLines == [family], "\(painter): \(openLines)")
      #expect(openSurface.cells[0][1].spanWidth == 2, "\(painter)")
      #expect(openSurface.cells[0][2].continuationLeadX == 1, "\(painter)")
      #expect(openSurface.cells[0][3].character == "b", "\(painter)")
    }
  }

  @Test func setB045WrapPointOnWideGlyphKeepsContinuationMarkers() {
    // "ab漢cd" is one word-like token of width 6. At width 4 the first row
    // keeps three content cells, so the wide glyph cannot fit after "ab" and
    // starts the next row between two continuation markers.
    let expected = ["ab–", "–漢–", "–cd"]
    let layout = layoutText(for: "ab漢cd", width: 4)
    let layoutLines = layout.lines.map(\.text)
    #expect(layoutLines == expected, "\(layoutLines)")

    let bounds = CellRect(origin: .zero, size: .init(width: 4, height: 3))
    let node = DrawNode(
      identity: testIdentity("SetBRaster", "045"), bounds: bounds,
      commands: [SetBTextPainter.plain.command(bounds: bounds, line: "ab漢cd")])
    let surface = Rasterizer().rasterize(node, minimumSize: bounds.size)
    let lines = surface.lines
    #expect(lines == expected, "\(lines)")
    #expect(surface.cells[0][3] == .empty)
    #expect(surface.cells[1][0].character == "–")
    #expect(surface.cells[1][1].character == "漢")
    #expect(surface.cells[1][1].spanWidth == 2)
    #expect(surface.cells[1][2].continuationLeadX == 1)
    #expect(surface.cells[1][3].character == "–")
    #expect(surface.cells[2][3] == .empty)
  }

  @Test func setB046SoftHyphenAndZeroWidthSpaceNeverOccupyAVisibleCell() {
    // Both are format characters of width zero inside one token. The wrapped
    // output must show the visible letters only, with the row break after
    // "c", and no cell may be left holding the invisible character.
    for invisible in ["\u{00AD}", "\u{200B}"] {
      let content = "ab\(invisible)cd"
      #expect(content.count == 5, "\(content.unicodeScalars.map(\.value))")
      let layout = layoutText(for: content, width: 3)
      let rowWidths = layout.lines.map(\.cellWidth)
      #expect(rowWidths == [3, 1], "\(rowWidths)")
      #expect(layout.lines.last?.text == "d")

      let bounds = CellRect(origin: .zero, size: .init(width: 3, height: 2))
      let node = DrawNode(
        identity: testIdentity("SetBRaster", "046"), bounds: bounds,
        commands: [SetBTextPainter.plain.command(bounds: bounds, line: content)])
      let surface = Rasterizer().rasterize(node, minimumSize: bounds.size)
      let lines = surface.lines
      #expect(lines == ["abc", "d"], "\(invisible.unicodeScalars.map(\.value)): \(lines)")
      let invisibleCharacter = Character(invisible)
      let leaked = surface.cells.flatMap { $0 }.filter { $0.character == invisibleCharacter }
      #expect(leaked.isEmpty, "\(leaked)")
      #expect(surface.cells[0][2].character == "c")
      #expect(surface.cells[1][0].character == "d")
      #expect(surface.cells[1][1] == .empty)
    }
  }

  @Test func setB047ZeroAreaPathContourFillsNothingButStrokesALine() {
    // A contour with no area encloses no sub-pixel: the fill writes nothing,
    // so every cell stays untouched. The same contour stroked is a line.
    let filled = DefaultRenderer().render(
      SetBFlatLine().fill(Color.red).frame(width: 4, height: 2),
      context: .init(identity: testIdentity("SetBRaster", "047-fill")))
    let filledCells = filled.rasterSurface.cells
    #expect(filled.rasterSurface.size == CellSize(width: 4, height: 2))
    let painted = filledCells.flatMap { $0 }.filter { $0 != .empty }
    #expect(painted.isEmpty, "\(painted)")

    let stroked = DefaultRenderer().render(
      SetBFlatLine().stroke(Color.red).frame(width: 4, height: 2),
      context: .init(identity: testIdentity("SetBRaster", "047-stroke")))
    let strokedLines = stroked.rasterSurface.cells.map { row in String(row.map(\.character)) }
    #expect(strokedLines == ["    ", "\u{2809}\u{2809}\u{2809}\u{2809}"], "\(strokedLines)")
  }

  @Test func setB048CoincidentRadialStopsSplitAtTheirLocation() {
    // Two stops at the same location: the sampler returns the first color at
    // or inside it and the last color beyond it, through both walks.
    var radial = RadialGradient(
      colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 1.5)
    radial.gradient.stops = [
      .init(color: .red, location: 0.5),
      .init(color: .blue, location: 0.5),
    ]
    let bounds = CellRect(origin: .zero, size: .init(width: 3, height: 1))
    let prepared = PreparedRadialGradient(radial, aspectRatio: 2, bounds: bounds)
    #expect(prepared.support == nil)

    let node = DrawNode(
      identity: testIdentity("SetBRaster", "048"), bounds: bounds,
      commands: [
        .fill(
          bounds: bounds, geometry: .rectangle, insetAmount: 0,
          style: .radialGradient(radial), mode: .full)
      ])
    let optimized = Rasterizer().rasterize(node, minimumSize: bounds.size)
    let reference = Rasterizer.$forceReferenceRadialWalk.withValue(true) {
      Rasterizer().rasterize(node, minimumSize: bounds.size)
    }
    let backgrounds = optimized.cells[0].map { $0.style?.backgroundColor }
    let expected: [Color?] = [.blue, .red, .blue]
    #expect(backgrounds == expected, "\(backgrounds)")
    #expect(reference == optimized)
  }

  @Test func setB049ForeignSurfaceOneCellChangeRepaintsIncrementally() {
    let bounds = CellRect(origin: .zero, size: .init(width: 3, height: 1))
    func node(_ characters: String) -> DrawNode {
      DrawNode(
        identity: testIdentity("SetBRaster", "049"), bounds: bounds,
        commands: [
          .foreignSurface(
            bounds: bounds,
            payload: SetBStaticPayload(
              grid: ForeignGrid(
                size: bounds.size, cells: [characters.map { RasterCell(character: $0) }])))
        ])
    }
    let before = node("ABC")
    let after = node("AXC")
    #expect(before.commands != after.commands)

    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let previous = rasterizer.rasterize(before, minimumSize: bounds.size)
    let fresh = rasterizer.rasterize(after, minimumSize: bounds.size)
    #expect(previous.lines == ["ABC"])
    #expect(fresh.lines == ["AXC"])

    // The diff names the one changed column, and that damage is enough for
    // the incremental path to reproduce the fresh surface.
    let damage = RasterSurfaceDamageDiff.diff(previous: previous, current: fresh)
    let expectedDamage = PresentationDamage(textRows: [.init(row: 0, columnRanges: [1..<2])])
    #expect(damage == expectedDamage, "\(String(describing: damage))")

    let incremental = rasterizer.rasterizeCollectingVisibleIdentities(
      after, minimumSize: bounds.size, previousSurface: previous, damage: damage)
    #expect(incremental.path == .incremental)
    #expect(incremental.incrementalMismatch == nil)
    #expect(incremental.surface == fresh)
    #expect(incremental.surface.cells[0][1].character == "X")
  }

  @Test func setB050OverlayBorderAddedThenRemovedUnderRetainedReuse() {
    let rootID = testIdentity("SetBRaster", "050")
    let contentID = testIdentity("SetBRaster", "050", "overlay-content")

    struct Bare: View {
      let contentID: Identity
      var body: some View {
        EmptyView()
          .frame(width: 6, height: 3)
          .background(Color.blue)
          .overlay { EmptyView().id(contentID) }
      }
    }
    struct Bordered: View {
      let contentID: Identity
      var body: some View {
        EmptyView()
          .frame(width: 6, height: 3)
          .background(Color.blue)
          .overlay { Rectangle().strokeBorder(Color.white).id(contentID) }
      }
    }

    // The mask contract, on a fresh frame with no identity routing involved:
    // the border's ring cells carry no background, the interior does.
    let reference = DefaultRenderer().render(
      EmptyView()
        .frame(width: 6, height: 3)
        .background(Color.blue)
        .overlay { Rectangle().strokeBorder(Color.white) },
      context: .init(identity: rootID)
    ).rasterSurface
    let referenceLines = reference.cells.map { row in String(row.map(\.character)) }
    #expect(referenceLines == ["┌────┐", "│    │", "└────┘"], "\(referenceLines)")
    for (y, row) in reference.cells.enumerated() {
      for (x, cell) in row.enumerated() {
        let isRing = y == 0 || y == 2 || x == 0 || x == 5
        let background = cell.style?.backgroundColor
        if isRing {
          #expect(background == nil, "ring cell (\(x), \(y)): \(cell)")
        } else {
          #expect(background == .blue, "interior cell (\(x), \(y)): \(cell)")
        }
      }
    }

    // Add the border, then remove it again, invalidating only the overlay
    // content so the base subtree is served from retained state each time.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let first = renderer.render(Bare(contentID: contentID), context: .init(identity: rootID))
    #expect(first.rasterSurface.size == CellSize(width: 6, height: 3))

    let added = renderer.render(
      Bordered(contentID: contentID),
      context: .init(identity: rootID, invalidatedIdentities: [contentID]))
    let addedFresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
      Bordered(contentID: contentID), context: .init(identity: rootID))
    #expect(added.diagnostics.work.resolvedNodesReused > 0)
    #expect(addedFresh.rasterSurface == reference)
    #expect(added.rasterSurface == reference)

    let removed = renderer.render(
      Bare(contentID: contentID),
      context: .init(identity: rootID, invalidatedIdentities: [contentID]))
    let removedFresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
      Bare(contentID: contentID), context: .init(identity: rootID))
    #expect(removed.diagnostics.work.resolvedNodesReused > 0)
    #expect(removed.rasterSurface == removedFresh.rasterSurface)
    #expect(removed.rasterSurface == first.rasterSurface)
    let removedCells = removed.rasterSurface.cells.flatMap { $0 }
    #expect(removedCells.count == 18)
    let stale = removedCells.filter { $0.character != " " || $0.style?.backgroundColor != .blue }
    #expect(stale.isEmpty, "\(stale)")
  }
}

/// The two text painters whose clipping rules can diverge: wrapped text goes
/// through layout, preformatted text through `clusterize`.
private enum SetBTextPainter: CaseIterable, Sendable {
  case plain
  case preformatted

  func command(
    bounds: CellRect, line: String, style: TextStyle = .init(foregroundStyle: .color(.cyan))
  ) -> DrawCommand {
    switch self {
    case .plain:
      return .text(
        bounds: bounds, content: line, style: style, lineLimit: nil, truncationMode: .tail,
        wrappingStrategy: .wordBoundary)
    case .preformatted:
      return .preformattedText(bounds: bounds, lines: [line], style: style)
    }
  }
}

/// A styled five-cell underlay whose cells must survive clipped writes above it.
private func setBUnderlayCommand(bounds: CellRect) -> DrawCommand {
  .preformattedText(
    bounds: bounds, lines: ["ABCDE"],
    style: .init(foregroundStyle: .color(.yellow), backgroundStyle: .color(.blue)))
}

private struct SetBStaticPayload: ForeignSurfacePayload {
  let grid: ForeignGrid
}

/// A closed contour with no area: a line across the middle of the unit rect.
private struct SetBFlatLine: Shape {
  func path(in rect: Rect) -> Path {
    let midY = rect.origin.y + rect.size.height / 2
    return Path { path in
      path.move(to: Point(x: rect.origin.x, y: midY))
      path.addLine(to: Point(x: rect.origin.x + rect.size.width, y: midY))
      path.closeSubpath()
    }
  }
}
