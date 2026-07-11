import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressRenderReconciliationTests {}

private func renderStressText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: Input-keyed canvas redraw

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 001 keyed canvas redraws its current marker")
  func renderReconciliation001KeyedCanvasRedrawsCurrentMarker() {
    // Hypothesis: Canvas disables retained phase extraction, but an enclosing retained frame
    // can still substitute an earlier DrawNode when the input-keyed payload changes in place.
    struct Root: View {
      let markerColumn: Int

      var body: some View {
        Canvas(markerColumn) { context, markerColumn in
          context.setCell(
            at: CellPoint(x: markerColumn, y: 0),
            character: "X",
            foreground: .green
          )
        }
        .frame(width: 5, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation001")

    for generation in 0..<16 {
      let expectedColumn = generation % 5
      let frame = renderer.render(
        Root(markerColumn: expectedColumn),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      for column in 0..<5 {
        #expect(
          frame.rasterSurface.cells[0][column].character
            == (column == expectedColumn ? "X" : " ")
        )
      }
    }
  }
}


// MARK: - Attempt 002: Recreated closure canvas capture

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 002 closure canvas uses its current capture")
  func renderReconciliation002ClosureCanvasUsesCurrentCapture() {
    // Hypothesis: closure-backed Canvas payloads intentionally compare by storage identity, but
    // retained draw substitution may still replay the first closure after repeated reconstruction.
    struct Root: View {
      let generation: Int

      var body: some View {
        Canvas { context in
          context.setCell(
            at: CellPoint(x: generation % 4, y: 0),
            character: Character(String(generation % 10)),
            foreground: .blue
          )
        }
        .frame(width: 4, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation002")

    for generation in 0..<16 {
      let frame = renderer.render(
        Root(generation: generation),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let expectedColumn = generation % 4
      #expect(
        frame.rasterSurface.cells[0][expectedColumn].character
          == Character(String(generation % 10))
      )
      #expect(
        frame.rasterSurface
          == DefaultRenderer().render(
            Root(generation: generation),
            context: .init(identity: rootIdentity)
          ).rasterSurface
      )
    }
  }
}


// MARK: - Attempt 003: Canvas grid churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 003 canvas grid follows every current frame")
  func renderReconciliation003CanvasGridFollowsCurrentFrame() {
    // Hypothesis: retained draw state may key Canvas only by drawing equality and overlook a
    // changed packing grid, replaying Braille cells after the author switches to quadrant cells.
    struct Dot: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setPixel(at: Point(x: 0.25, y: 0.25))
        context.setPixel(at: Point(x: 0.75, y: 0.75))
      }
    }

    struct Root: View {
      let grid: CanvasGrid

      var body: some View {
        Canvas(Dot(), grid: grid)
          .frame(width: 2, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation003")
    let grids: [CanvasGrid] = [.braille2x4, .quadrant2x2, .verticalHalfBlock]

    for generation in 0..<18 {
      let root = Root(grid: grids[generation % grids.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.rasterSurface.cells[0][0].character != " ")
    }
  }
}


// MARK: - Attempt 004: Canvas geometry churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 004 canvas context tracks oscillating geometry")
  func renderReconciliation004CanvasContextTracksOscillatingGeometry() {
    // Hypothesis: a retained Canvas DrawNode may invoke its drawing with the cached frame size
    // after the same identity revisits an earlier measurement-cache proposal.
    struct CurrentCorner: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setCell(
          at: CellPoint(x: max(0, context.size.width - 1), y: max(0, context.size.height - 1)),
          character: "C",
          foreground: .green
        )
      }
    }

    struct Root: View {
      let width: Int
      let height: Int

      var body: some View {
        Canvas(CurrentCorner())
          .frame(width: width, height: height)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation004")
    let sizes = [(2, 1), (7, 3), (3, 2), (6, 1), (2, 3)]

    for generation in 0..<20 {
      let size = sizes[generation % sizes.count]
      let frame = renderer.render(
        Root(width: size.0, height: size.1),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(frame.rasterSurface.size == CellSize(width: size.0, height: size.1))
      #expect(frame.rasterSurface.cells[size.1 - 1][size.0 - 1].character == "C")
    }
  }
}


// MARK: - Attempt 005: Direct-cell Canvas style churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 005 direct canvas cells keep current glyph and style")
  func renderReconciliation005DirectCanvasCellsKeepCurrentGlyphAndStyle() {
    // Hypothesis: direct-cell Canvas writes can retain a prior cell payload independently from
    // the Braille buffer, producing a current glyph with a stale foreground or background.
    struct StyledCell: CanvasDrawing, Equatable {
      let generation: Int

      func draw(into context: inout CanvasContext) {
        context.setCell(
          at: .zero,
          character: generation.isMultiple(of: 2) ? "A" : "B",
          foreground: generation.isMultiple(of: 3) ? .red : .green,
          background: generation.isMultiple(of: 2) ? .blue : .white
        )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation005")

    for generation in 0..<18 {
      let root = Canvas(StyledCell(generation: generation)).frame(width: 1, height: 1)
      let frame = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let cell = frame.rasterSurface.cells[0][0]
      #expect(cell.character == (generation.isMultiple(of: 2) ? "A" : "B"))
      #expect(cell.style?.foregroundColor == (generation.isMultiple(of: 3) ? .red : .green))
      #expect(cell.style?.backgroundColor == (generation.isMultiple(of: 2) ? .blue : .white))
    }
  }
}


// MARK: - Attempt 006: Canvas inherited foreground churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 006 canvas resolves the current inherited foreground")
  func renderReconciliation006CanvasResolvesCurrentInheritedForeground() {
    // Hypothesis: Canvas disables retained phase extraction at its payload, while its inherited
    // style lives in placed metadata; partial reuse may therefore pair the old style with new dots.
    struct UnstyledDot: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setPixel(at: .zero)
      }
    }

    struct Root: View {
      let useRed: Bool

      var body: some View {
        Canvas(UnstyledDot())
          .frame(width: 1, height: 1)
          .foregroundStyle(useRed ? Color.red : Color.blue)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation006")

    for generation in 0..<16 {
      let useRed = generation.isMultiple(of: 2)
      let frame = renderer.render(
        Root(useRed: useRed),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(
        frame.rasterSurface.cells[0][0].style?.foregroundColor
          == (useRed ? Color.red : Color.blue)
      )
    }
  }
}


// MARK: - Attempt 007: Canvas reinsertion beside retained content

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 007 canvas reinsertion preserves adjacent retained draw")
  func renderReconciliation007CanvasReinsertionPreservesAdjacentRetainedDraw() {
    // Hypothesis: removing an unsupported retained-phase subtree may shift the retained draw
    // lookup so its former DrawNode is substituted for the stable sibling that follows it.
    struct Marker: CanvasDrawing, Equatable {
      let generation: Int

      func draw(into context: inout CanvasContext) {
        context.setCell(at: .zero, character: Character(String(generation % 10)))
      }
    }

    struct Root: View {
      let generation: Int

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          if generation.isMultiple(of: 2) {
            Canvas(Marker(generation: generation))
              .frame(width: 1, height: 1)
          }
          Text("Stable tail")
            .id("render-reconciliation-007-tail")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation007")

    for generation in 0..<18 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(renderStressText(retained).contains("Stable tail"))
    }
  }
}


// MARK: - Attempt 008: Stable-ID Canvas and Text payload swap

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 008 stable identity replaces canvas and text draw payloads")
  func renderReconciliation008StableIdentityReplacesCanvasAndTextPayloads() {
    // Hypothesis: the retained draw map has a runtime-identity fallback after its ViewNodeID
    // lookup, so a stable explicit ID may resurrect an incompatible Canvas DrawNode for Text.
    struct Marker: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setCell(at: .zero, character: "K", foreground: .green)
      }
    }

    struct Root: View {
      let showCanvas: Bool

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          if showCanvas {
            Canvas(Marker())
              .frame(width: 12, height: 1)
              .id("render-reconciliation-008-payload")
          } else {
            Text("Text payload")
              .frame(width: 12, height: 1, alignment: .leading)
              .id("render-reconciliation-008-payload")
          }
          Text("Footer")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation008")

    for generation in 0..<16 {
      let showCanvas = generation.isMultiple(of: 2)
      let root = Root(showCanvas: showCanvas)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(renderStressText(retained).contains(showCanvas ? "K" : "Text payload"))
    }
  }
}


// MARK: - Attempt 009: Line-limit cache churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 009 line limit removal restores every current line")
  func renderReconciliation009LineLimitRemovalRestoresEveryCurrentLine() {
    // Hypothesis: TextLayoutCache includes lineLimit, but retained measurement may reuse a
    // truncated MeasuredNode when the modifier repeatedly returns to the same proposal.
    struct Root: View {
      let lineLimit: Int?

      var body: some View {
        Text("ALPHA BETA GAMMA DELTA")
          .lineLimit(lineLimit)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation009")
    let proposal = ProposedSize(width: 6, height: nil)

    for generation in 0..<18 {
      let limit = generation.isMultiple(of: 2) ? 1 : nil
      let root = Root(lineLimit: limit)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: proposal
      )
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.rasterSurface.size.height == (limit == nil ? 4 : 1))
    }
  }
}


// MARK: - Attempt 010: Truncation-mode cache churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 010 truncation mode never replays a prior edge")
  func renderReconciliation010TruncationModeNeverReplaysPriorEdge() {
    // Hypothesis: the text-layout cache separates truncation modes, while retained placement
    // equivalence may not, causing head, middle, and tail output to alias after cycling.
    struct Root: View {
      let mode: Text.TruncationMode

      var body: some View {
        Text("ABCDEFGHIJKLMN")
          .lineLimit(1)
          .truncationMode(mode)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation010")
    let proposal = ProposedSize(width: 7, height: nil)
    let modes: [Text.TruncationMode] = [.head, .middle, .tail]

    for generation in 0..<18 {
      let root = Root(mode: modes[generation % modes.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: proposal
      )
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(renderStressText(retained).contains("…"))
    }
  }
}


// MARK: - Attempt 011: Measurement-cache proposal LRU revisit

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 011 evicted proposal revisit matches a fresh layout")
  func renderReconciliation011EvictedProposalRevisitMatchesFreshLayout() {
    // Hypothesis: MeasurementCache keeps four proposals per node and uses a generational access
    // deque; repeated hits plus eviction can leave a stale generation record that evicts the
    // newly stored value when an old width is revisited.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation011")
    let widths = [2, 7, 3, 8, 4, 9, 2, 8, 3, 9, 4, 7, 2]

    for generation in widths.indices {
      let width = widths[generation]
      let root = Text("proposal cache revisit")
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: .init(width: width, height: nil)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: .init(width: width, height: nil)
      )
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
    }
  }
}


// MARK: - Attempt 012: Equal-scalar wide-glyph churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 012 equal scalar counts remeasure terminal cell width")
  func renderReconciliation012EqualScalarCountsRemeasureTerminalCellWidth() {
    // Hypothesis: a relaxed text measurement signature may mistake equal scalar counts for equal
    // cell width, retaining one-line ASCII geometry for a same-count wide-glyph replacement.
    struct Root: View {
      let content: String

      var body: some View {
        Text(content)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation012")
    let contents = ["AAAA", "界界界界", "BBBB", "語語語語"]
    let proposal = ProposedSize(width: 4, height: nil)

    for generation in 0..<20 {
      let content = contents[generation % contents.count]
      let root = Root(content: content)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: proposal
      )
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(renderStressText(retained).contains(String(content.prefix(1))))
    }
  }
}


// MARK: - Attempt 013: Combining and precomposed scalar churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 013 combining forms stay distinct in retained text")
  func renderReconciliation013CombiningFormsStayDistinctInRetainedText() {
    // Hypothesis: text cache equality or retained draw equivalence may normalize canonically
    // equivalent graphemes, replaying the earlier scalar spelling despite a new authored value.
    struct Root: View {
      let content: String

      var body: some View {
        Text(content)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation013")
    let contents = ["e\u{301}X", "éX", "o\u{308}Y", "öY"]

    for generation in 0..<20 {
      let content = contents[generation % contents.count]
      let root = Root(content: content)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(retained.rasterSurface.lines == [content])
      #expect(
        retained.rasterSurface
          == DefaultRenderer().render(
            root,
            context: .init(identity: rootIdentity)
          ).rasterSurface
      )
    }
  }
}


// MARK: - Attempt 014: Explicit-newline topology churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 014 explicit newline topology follows current content")
  func renderReconciliation014ExplicitNewlineTopologyFollowsCurrentContent() {
    // Hypothesis: equal total cell counts with different explicit-newline boundaries can collide
    // in retained measurement, leaving the current glyphs placed on the previous line topology.
    struct Root: View {
      let content: String

      var body: some View {
        Text(content)
          .frame(width: 6, alignment: .leading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation014")
    let contents = ["AA\nBBBB", "AAAA\nBB", "A\nB\nC\nD", "ABCDEF"]

    for generation in 0..<20 {
      let root = Root(content: contents[generation % contents.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
    }
  }
}


// MARK: - Attempt 015: Rich and plain text payload swap

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 015 equal visible rich and plain text replace draw payload")
  func renderReconciliation015EqualVisibleRichAndPlainTextReplaceDrawPayload() {
    // Hypothesis: Text and RichText can have equal visible content but different draw payload
    // structure; relaxed measurement reuse must not let retained draw extraction keep old runs.
    struct Root: View {
      let rich: Bool

      var body: some View {
        if rich {
          Text("Same \(Text("payload").bold())")
            .id("render-reconciliation-015-text")
        } else {
          Text("Same payload")
            .id("render-reconciliation-015-text")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation015")

    for generation in 0..<16 {
      let root = Root(rich: generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(renderStressText(retained).contains("Same payload"))
    }
  }
}


// MARK: - Attempt 016: Equal-width draw-only text churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 016 equal width text updates amid retained siblings")
  func renderReconciliation016EqualWidthTextUpdatesAmidRetainedSiblings() {
    // Hypothesis: measurement-equivalent text payloads intentionally reuse geometry, but retained
    // DrawNode substitution may then preserve the first glyphs under a current resolved payload.
    struct Root: View {
      let value: String

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Stable header").id("render-reconciliation-016-header")
          Text(value).id("render-reconciliation-016-value")
          Text("Stable footer").id("render-reconciliation-016-footer")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation016")
    let values = ["ALPHA", "BRAVO", "CHARL", "DELTA"]

    for generation in 0..<24 {
      let value = values[generation % values.count]
      let root = Root(value: value)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(renderStressText(retained).contains(value))
      #expect(
        retained.rasterSurface
          == DefaultRenderer().render(
            root,
            context: .init(identity: rootIdentity)
          ).rasterSurface
      )
    }
  }
}


// MARK: - Attempt 017: Foreground-style retained draw churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 017 retained text uses its current foreground")
  func renderReconciliation017RetainedTextUsesCurrentForeground() {
    // Hypothesis: a draw-only environment change reuses measurement and placement, leaving the
    // retained DrawNode's resolved style stale when the same colors recur out of order.
    struct Root: View {
      let color: Color

      var body: some View {
        Text("COLOR")
          .foregroundStyle(color)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation017")
    let colors: [Color] = [.red, .green, .blue, .white, .green, .red]

    for generation in 0..<24 {
      let color = colors[generation % colors.count]
      let frame = renderer.render(
        Root(color: color),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(frame.rasterSurface.cells[0][0].style?.foregroundColor == color)
      #expect(frame.diagnostics.work.measuredNodesComputed == (generation == 0 ? 1 : 0))
    }
  }
}


// MARK: - Attempt 018: Opacity retained draw churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 018 opacity oscillation matches a fresh raster")
  func renderReconciliation018OpacityOscillationMatchesFreshRaster() {
    // Hypothesis: opacity is mirrored into retained placed metadata and draw commands; partial
    // metadata synchronization may update one phase while raster reuses the earlier alpha.
    struct Root: View {
      let opacity: Double

      var body: some View {
        Text("OPACITY")
          .foregroundStyle(Color.red)
          .opacity(opacity)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation018")
    let opacities = [1.0, 0.25, 0.0, 0.75, 0.5, 1.0]

    for generation in 0..<24 {
      let root = Root(opacity: opacities[generation % opacities.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}


// MARK: - Attempt 019: Border set and side churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 019 border set and sides replace retained commands")
  func renderReconciliation019BorderSetAndSidesReplaceRetainedCommands() {
    // Hypothesis: BorderSet and active sides live in draw metadata around stable child geometry;
    // retained command extraction may keep corners or edges from a prior set after cycling.
    struct Root: View {
      let set: BorderSet
      let sides: Edge.Set

      var body: some View {
        Text("B")
          .frame(width: 5, height: 3)
          .border(Color.green, set: set, placement: .inset, sides: sides)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation019")
    let variants: [(BorderSet, Edge.Set)] = [
      (.single, .all),
      (.double, .horizontal),
      (.heavy, .vertical),
      (.rounded, [.top, .leading]),
    ]

    for generation in 0..<20 {
      let variant = variants[generation % variants.count]
      let root = Root(set: variant.0, sides: variant.1)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}


// MARK: - Attempt 020: Clip enable and disable churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 020 removing clip restores current overflow")
  func renderReconciliation020RemovingClipRestoresCurrentOverflow() {
    // Hypothesis: retained draw extraction may preserve an ancestor clip command after the
    // clipping modifier disappears, because child measurement stays fixed across both branches.
    struct Root: View {
      let clipped: Bool

      var body: some View {
        if clipped {
          Text("ABCDEFG")
            .fixedSize()
            .frame(width: 3, alignment: .leading)
            .clipped()
            .id("render-reconciliation-020")
        } else {
          Text("ABCDEFG")
            .fixedSize()
            .frame(width: 3, alignment: .leading)
            .id("render-reconciliation-020")
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation020")

    for generation in 0..<18 {
      let root = Root(clipped: generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}


// MARK: - Attempt 021: Background alignment churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 021 background follows current alignment")
  func renderReconciliation021BackgroundFollowsCurrentAlignment() {
    // Hypothesis: a retained background subtree can reuse its earlier placement because its
    // authored content is unchanged even when the wrapper's alignment metadata changes.
    struct Root: View {
      let alignment: Alignment

      var body: some View {
        Text("F")
          .frame(width: 7, height: 3)
          .background(alignment: alignment) {
            Text("B")
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation021")
    let alignments: [Alignment] = [.topLeading, .bottomTrailing, .center, .topTrailing]

    for generation in 0..<20 {
      let root = Root(alignment: alignments[generation % alignments.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}


// MARK: - Attempt 022: Overlay alignment churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 022 overlay follows current alignment")
  func renderReconciliation022OverlayFollowsCurrentAlignment() {
    // Hypothesis: an overlay's hosted identity stays stable across placement-only changes, so
    // retained placement may preserve its previous origin while the base remains unchanged.
    struct Root: View {
      let alignment: Alignment

      var body: some View {
        Text("BASE")
          .frame(width: 8, height: 4, alignment: .center)
          .overlay(alignment: alignment) {
            Text("O")
          }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation022")
    let alignments: [Alignment] = [.topLeading, .bottomTrailing, .center, .bottomLeading]

    for generation in 0..<20 {
      let root = Root(alignment: alignments[generation % alignments.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}


// MARK: - Attempt 023: Frame alignment churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 023 frame alignment relocates stable child")
  func renderReconciliation023FrameAlignmentRelocatesStableChild() {
    // Hypothesis: retained placement equivalence can preserve frame geometry while overlooking
    // the alignment value that changes only the stable child's origin inside that frame.
    struct Root: View {
      let alignment: Alignment

      var body: some View {
        Text("X")
          .frame(width: 9, height: 5, alignment: alignment)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation023")
    let alignments: [Alignment] = [.topLeading, .bottomTrailing, .center, .top, .leading]

    for generation in 0..<25 {
      let root = Root(alignment: alignments[generation % alignments.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.placedTree == fresh.placedTree)
    }
  }
}


// MARK: - Attempt 024: Padding edge and amount churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 024 asymmetric padding replaces retained insets")
  func renderReconciliation024AsymmetricPaddingReplacesRetainedInsets() {
    // Hypothesis: inset behavior equivalence or measurement caching may coalesce different
    // asymmetric EdgeInsets with the same total size, retaining the previous content origin.
    struct Root: View {
      let insets: EdgeInsets

      var body: some View {
        Text("P")
          .padding(insets)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation024")
    let variants = [
      EdgeInsets(top: 0, leading: 3, bottom: 2, trailing: 0),
      EdgeInsets(top: 2, leading: 0, bottom: 0, trailing: 3),
      EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 1),
      EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 2),
    ]

    for generation in 0..<24 {
      let root = Root(insets: variants[generation % variants.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.placedTree == fresh.placedTree)
    }
  }
}


// MARK: - Attempt 025: Layout-priority allocation churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 025 layout priority swaps scarce width allocation")
  func renderReconciliation025LayoutPrioritySwapsScarceWidthAllocation() {
    // Hypothesis: layoutPriority is a retained measurement input, but equal aggregate intrinsic
    // sizes may let the HStack preserve its earlier per-child allocation after priorities swap.
    struct Root: View {
      let favorLeft: Bool

      var body: some View {
        HStack(spacing: 0) {
          Text("LEFT").layoutPriority(favorLeft ? 1 : 0)
          Text("RIGHT").layoutPriority(favorLeft ? 0 : 1)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation025")
    let proposal = ProposedSize(width: 7, height: 1)

    for generation in 0..<20 {
      let root = Root(favorLeft: generation.isMultiple(of: 2))
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        ),
        proposal: proposal
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: rootIdentity),
        proposal: proposal
      )
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.placedTree == fresh.placedTree)
    }
  }
}

// MARK: - End
