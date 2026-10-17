import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

#if !canImport(WASILibc)
  @MainActor
  @Suite(.serialized)
  struct AdversarialSetATerminalOutputTests {
    @Test func setA451RemovingEmphasisResetsTheWholePreviousStyle() {
      // Hypothesis: retaining an unchanged foreground skips the reset that removes
      // reverse, blink, bold, and strike from the next, merely italic glyph.
      let first = ResolvedTextStyle(
        foregroundColor: Color(hexRGB: 0x123456),
        emphasis: [.bold, .blink, .reverse], strikethroughStyle: .init())
      let second = ResolvedTextStyle(
        foregroundColor: Color(hexRGB: 0x123456), emphasis: .italic)
      let output = render([
        .init(character: "A", style: first), .init(character: "B", style: second),
        .init(character: "C"),
      ])
      #expect(output == "\u{1B}[1;5;7;9;38;2;18;52;86mA\u{1B}[0m\u{1B}[3;38;2;18;52;86mB\u{1B}[0mC")
    }

    @Test func setA452ColorlessStylingRetainsNonColorDecorations() {
      // Hypothesis: the color-none branch suppresses independent emphasis and
      // underline codes, or accidentally emits an extended underline color.
      let profile = TerminalCapabilityProfile(
        glyphLevel: .unicode, colorLevel: .none, emitsStyleEscapeSequences: true)
      let style = ResolvedTextStyle(
        foregroundColor: .red, backgroundColor: .blue, emphasis: [.bold, .italic],
        underlineStyle: .init(pattern: .double, color: .green), opacity: 0.5)
      #expect(
        render([.init(character: "X", style: style)], profile: profile)
          == "\u{1B}[1;2;3;4:2mX\u{1B}[0m")
    }

    @Test func setA453ExtendedUnderlineColorCannotOverwriteForegroundOrBackground() {
      // Hypothesis: ANSI-256 underline color reuses the foreground/background
      // selector or fails to clamp valid out-of-gamut device components.
      let style = ResolvedTextStyle(
        foregroundColor: Color(red: 2, green: -1, blue: 0),
        backgroundColor: Color(hexRGB: 0x00FF00),
        underlineStyle: .init(pattern: .curly, color: Color(hexRGB: 0x0000FF)))
      #expect(
        render([.init(character: "U", style: style)], profile: .ansi256)
          == "\u{1B}[4:3;38;5;196;48;5;46;58;5;21mU\u{1B}[0m")
    }

    @Test func setA454ClosingARenderStateInvalidatesItsRawStyleShortcut() {
      // Hypothesis: closing a run resets terminal SGR but leaves the raw-style
      // optimization warm, so an identical next run is emitted without its style.
      let renderer = TerminalCellTextRenderer(capabilityProfile: .trueColor)
      var state = TerminalCellTextRenderer.RenderState()
      var output = ""
      let row = [RasterCell(character: "X", style: .init(emphasis: .bold))]
      renderer.appendRenderedCells(in: row, from: 0, to: 1, into: &output, state: &state)
      renderer.closeRenderState(&state, into: &output)
      renderer.appendRenderedCells(in: row, from: 0, to: 1, into: &output, state: &state)
      renderer.closeRenderState(&state, into: &output)
      #expect(output == "\u{1B}[1mX\u{1B}[0m\u{1B}[1mX\u{1B}[0m")
    }

    @Test func setA455TransparentForegroundAndUnderlineUseTheCellBackdrop() throws {
      // Hypothesis: terminal alpha resolution uses the host background for ink
      // and underline even when the cell has its own opaque background.
      let renderer = TerminalSurfaceRenderer(
        capabilityProfile: .trueColor, terminalBackgroundColor: Color(hexRGB: 0xFFFFFF))
      let style = ResolvedTextStyle(
        foregroundColor: Color(hexRGB: 0x0000FF, alpha: 0),
        backgroundColor: Color(hexRGB: 0xFF0000),
        underlineStyle: .init(color: Color(hexRGB: 0x00FF00, alpha: 0)))
      let output = renderer.render(surface([[.init(character: "X", style: style)]]))
      let parameters = output.dropFirst(2).prefix { $0 != "m" }
        .split(separator: ";").compactMap { Int($0) }
      try #require(parameters.count == 16)
      #expect(Array(parameters[6...10]) == [48, 2, 255, 0, 0])
      #expect(Array(parameters[0...2]) == [4, 38, 2])
      #expect(Array(parameters[11...12]) == [58, 2])
      // A one-byte tolerance isolates backdrop selection from color-space
      // round-trip precision: both transparent decorations must resolve red.
      for start in [3, 13] {
        #expect(abs(parameters[start] - 255) <= 1)
        #expect(parameters[start + 1] <= 1 && parameters[start + 2] <= 1)
      }
    }

    @Test func setA456MultilineHyperlinksCloseBeforeEveryLineSeparator() {
      // Hypothesis: a link spanning authored rows remains open through CRLF,
      // linking terminal whitespace or allowing the next render to inherit it.
      let destination = "https://example.test/multiline"
      let raster = surface([
        [.init(character: "A", hyperlink: destination)],
        [.init(character: "B", hyperlink: destination)],
      ])
      #expect(
        TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(raster)
          == open(destination) + "A" + close + "\r\n" + open(destination) + "B" + close)
    }

    @Test func setA457EightBitOSCControlsCannotTerminateAUnicodeDestination() {
      // Hypothesis: sanitization handles seven-bit ESC/ST but passes C1 OSC/ST,
      // letting an authored link terminate the OSC envelope before its label.
      let dirty = "https://example.test/é\u{9D}part\u{9C}\u{85}\u{7F}終"
      let clean = "https://example.test/épart終"
      #expect(render([.init(character: "L", hyperlink: dirty)]) == open(clean) + "L" + close)
    }

    @Test func setA458ChangingOnlyTheLinkCannotReuseThePreviousDestination() {
      // Hypothesis: the equal-style fast path bypasses a changed OSC8 destination,
      // so visually identical adjacent link labels share the first target.
      let style = ResolvedTextStyle(emphasis: .bold)
      let output = render([
        .init(character: "A", style: style, hyperlink: "https://a.test"),
        .init(character: "B", style: style, hyperlink: "https://b.test"),
      ])
      #expect(
        output == open("https://a.test") + "\u{1B}[1mA" + close
          + open("https://b.test") + "B" + close + "\u{1B}[0m")
    }

    @Test func setA459RemovingALinkClosesItBeforeTheUnlinkedGlyph() {
      // Hypothesis: removing link metadata without changing SGR leaves the next
      // ordinary glyph inside the old OSC8 range until the row closes.
      let style = ResolvedTextStyle(emphasis: .italic)
      let output = render([
        .init(character: "L", style: style, hyperlink: "https://a.test"),
        .init(character: "N", style: style),
      ])
      #expect(output == open("https://a.test") + "\u{1B}[3mL" + close + "N\u{1B}[0m")
    }

    @Test func setA460DisablingSGRDoesNotDisableOrUnbalanceOSC8() {
      // Hypothesis: style-output suppression also bypasses hyperlink transitions
      // or emits a trailing SGR reset when closing an independently enabled link.
      let profile = TerminalCapabilityProfile(
        glyphLevel: .unicode, colorLevel: .trueColor, emitsStyleEscapeSequences: false,
        supportsHyperlinks: true)
      let output = render(
        [
          .init(character: "L", style: .init(emphasis: .bold), hyperlink: "https://a.test"),
          .init(character: "N", style: .init(emphasis: .italic)),
        ], profile: profile)
      #expect(output == open("https://a.test") + "L" + close + "N")
    }

    @Test func setA461ColoredTailSpacesCannotBecomeDefaultEraseCells() throws {
      // Hypothesis: erase-to-EOL lowering treats painted spaces like blank cells
      // and loses their background after the row's SGR reset.
      let before = surface([[.init(character: "A"), .init(character: "B"), .init(character: "C")]])
      let after = surface([
        [
          .init(character: "A"),
          .init(style: .init(backgroundColor: Color(hexRGB: 0xFF0000))),
          .init(style: .init(backgroundColor: Color(hexRGB: 0xFF0000))),
        ]
      ])
      let plan = planner().plan(previousSurface: before, currentSurface: after)
      let batch = try #require(plan.rowBatches.first)
      #expect(!batch.canLowerToEraseToEndOfLine(surfaceWidth: 3))
      let output = emission(after, plan: plan).output
      #expect(output == "\u{1B}[1;2H\u{1B}[48;2;255;0;0m  \u{1B}[0m")
      #expect(!output.contains("\u{1B}[K"))
    }

    @Test func setA462LinkedWhitespaceCannotBeErasedAsAnUnlinkedTail() throws {
      // Hypothesis: plain-looking tail spaces take the erase fast path despite
      // carrying a clickable OSC8 range that must be explicitly painted.
      let before = RasterSurface(size: .init(width: 3, height: 1), lines: ["ABC"])
      let after = surface([
        [
          .init(character: "A"),
          .init(hyperlink: "https://space.test"), .init(hyperlink: "https://space.test"),
        ]
      ])
      let plan = planner().plan(previousSurface: before, currentSurface: after)
      #expect(try #require(plan.rowBatches.first).cellsChanged == 2)
      #expect(
        emission(after, plan: plan).output
          == "\u{1B}[1;2H" + open("https://space.test") + "  " + close)
    }

    @Test func setA463InteriorBlankDamageCannotEraseTheUnchangedSuffix() throws {
      // Hypothesis: a one-span blank edit is lowered to EL without checking
      // whether live cells remain to its right.
      let before = RasterSurface(size: .init(width: 5, height: 1), lines: ["ABCDE"])
      let after = RasterSurface(size: before.size, lines: ["A  DE"])
      let plan = planner().plan(previousSurface: before, currentSurface: after)
      #expect(try #require(plan.rowBatches.first).cellsChanged == 2)
      #expect(emission(after, plan: plan).output == "\u{1B}[1;2H  ")
    }

    @Test func setA464DisjointDirtySpansUseCellDistanceWithoutRepaintingTheGap() throws {
      // Hypothesis: batching carries the span length instead of its ending
      // column and places a later edit over unchanged gap cells.
      let before = RasterSurface(size: .init(width: 9, height: 1), lines: ["abcdefghi"])
      let after = RasterSurface(size: before.size, lines: ["aXcdefYhi"])
      let plan = planner().plan(previousSurface: before, currentSurface: after)
      let batch = try #require(plan.rowBatches.first)
      #expect(batch.anchorColumn == 1 && batch.cellsChanged == 2)
      #expect(batch.spanUpdates.map(\.column) == [1, 6])
      #expect(emission(after, plan: plan).output == "\u{1B}[1;2HX\u{1B}[4CY")
    }

    @Test func setA465DirtyRowsCloseStyleAndLinkBeforeMovingToTheNextRow() {
      // Hypothesis: incremental row batching reuses terminal state across row
      // anchors, leaking a styled link into a separately dirty plain row.
      let before = RasterSurface(size: .init(width: 1, height: 2), lines: ["a", "b"])
      let after = surface([
        [.init(character: "X", style: .init(emphasis: .bold), hyperlink: "https://a.test")],
        [.init(character: "Y")],
      ])
      let plan = planner().plan(previousSurface: before, currentSurface: after)
      #expect(plan.rowBatches.count == 2)
      #expect(
        emission(after, plan: plan).output == "\u{1B}[1;1H" + open("https://a.test")
          + "\u{1B}[1mX" + close + "\u{1B}[0m\u{1B}[2;1HY")
    }

    @Test func setA466SkippedBlankRowsKeepAbsoluteFullRepaintCoordinates() {
      // Hypothesis: omitting empty full-repaint rows changes the cursor's logical
      // row, collapsing later content upward after a full-width preceding row.
      let raster = RasterSurface(size: .init(width: 3, height: 4), lines: ["ABC", "", "", "XYZ"])
      let output = emission(raster, plan: .fullRepaint(surfaceSize: raster.size)).output
      #expect(output == "\u{1B}[2J\u{1B}[1;1HABC\u{1B}[4;1HXYZ")
      #expect(!output.contains("\n") && !output.contains("\r"))
    }

    @Test func setA467AuthoredCRLFAndC1ControlsCannotAddTerminalCommands() {
      // Hypothesis: the control filter sees CRLF as a multi-scalar Character
      // and lets it, eight-bit CSI, or BEL survive as terminal output controls.
      let source = "a\r\nb\u{9B}31mc\u{7}d"
      let row = source.map { RasterCell(character: $0) }
      #expect(render(row) == "a�b�31mc�d")
      #expect(render(row, profile: .previewASCII) == "a?b?31mc?d")
    }

    @Test func setA468ScrollOnlyFramesStillAcquireASynchronizedOutputEnvelope() throws {
      // Hypothesis: synchronization gates only on repaint batches and misses a
      // verified scroll that moves many rows without repainting any cells.
      var profile = TerminalCapabilityProfile.previewUnicode
      profile.supportsScrollRegions = true
      profile.supportsSynchronizedOutput = true
      let before = RasterSurface(size: .init(width: 4, height: 3), lines: ["AAAA", "BBBB", "CCCC"])
      let after = RasterSurface(size: before.size, lines: ["BBBB", "CCCC", ""])
      let plan = planner(profile).plan(
        previousSurface: before, currentSurface: after,
        translationCandidate: .init(
          band: .init(origin: .zero, size: before.size), dy: -1, baselineFrameOrdinal: 1))
      #expect(try #require(plan.scrollRegion).delta == -1)
      #expect(plan.rowBatches.isEmpty)
      let output = emission(after, plan: plan, profile: profile).output
      #expect(
        TerminalHostEscapeSequences.wrappedSynchronizedOutput(
          output, plan: plan, capabilityProfile: profile)
          == "\u{1B}[?2026h\u{1B}[1;3r\u{1B}[1S\u{1B}[r\u{1B}[1;1H\u{1B}[?2026l")
    }

    @Test func setA469ScrollRegionIsResetBeforeAnOutsideRowIsRepainted() throws {
      // Hypothesis: the scroll prefix leaves DECSTBM active while ordinary
      // dirty-row anchors repaint a footer outside the translated viewport.
      var profile = TerminalCapabilityProfile.previewUnicode
      profile.supportsScrollRegions = true
      let before = RasterSurface(
        size: .init(width: 4, height: 5), lines: ["HEAD", "AAAA", "BBBB", "CCCC", "old!"])
      let after = RasterSurface(size: before.size, lines: ["HEAD", "BBBB", "CCCC", "DDDD", "new!"])
      let plan = planner(profile).plan(
        previousSurface: before, currentSurface: after,
        translationCandidate: .init(
          band: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 3)), dy: -1,
          baselineFrameOrdinal: 1))
      #expect(try #require(plan.scrollRegion).topRow == 1)
      #expect(
        emission(after, plan: plan, profile: profile).output
          == "\u{1B}[2;4r\u{1B}[1S\u{1B}[r\u{1B}[1;1H\u{1B}[4;1HDDDD\u{1B}[5;1Hnew")
    }

    @Test func setA470ClipboardEncodingPreservesUTF8NULAndBase64Remainders() throws {
      // Hypothesis: the OSC52 encoder counts graphemes or truncates at NUL,
      // corrupting multibyte clipboard data and one/two-byte tail groups.
      let controller = TerminalOutputController()
      let host = host(controller)
      for text in ["é\u{0}🚀", "é\u{0}🚀x", "é\u{0}🚀xy"] {
        #expect(try host.writeClipboard(text))
        let output = try #require(controller.writes.last)
        #expect(output.hasPrefix("\u{1B}]52;c;") && output.hasSuffix("\u{7}"))
        let payload = String(output.dropFirst(7).dropLast())
        #expect(Data(base64Encoded: payload) == Data(text.utf8))
        #expect(output.filter { $0 == "\u{7}" }.count == 1)
      }
    }

    @Test func setA471ExitCleanupRetiresPixelMouseAndKeyboardBeforeLeavingItsScreen() {
      // Hypothesis: teardown switches screens before popping the per-screen
      // keyboard stack, or leaves pixel mouse interpretation enabled afterward.
      let output = TerminalHostEscapeSequences.processExitReset(
        mouseCoordinateMode: .pixels(
          metrics: .init(width: 8, height: 16, source: .reported), source: .terminalPixels),
        hoverEnabled: true, kittyKeyboardPushed: true)
      #expect(
        output == "\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1016l\u{1B}[?1006l"
          + "\u{1B}[<u\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l")
    }

    @Test func setA472ClearingTheAccessibilityCursorHidesItWithoutMovingIt() throws {
      // Hypothesis: a nil cursor target is lowered to origin+show, leaving an
      // accessibility cursor visible on unrelated content after focus is cleared.
      let controller = TerminalOutputController()
      let host = host(controller)
      try host.presentAccessibilityCursorFocus(at: .init(x: 3, y: 2))
      try host.drainPendingPresentation()
      try host.presentAccessibilityCursorFocus(at: nil)
      try host.drainPendingPresentation()
      #expect(controller.writes == ["\u{1B}[3;4H\u{1B}[?25h", "\u{1B}[?25l"])
    }

    @Test func setA473ASCIIFallbackKeepsWideGlyphCellWidthAndFollowingAnchor() {
      // Hypothesis: degrading a multi-scalar wide glyph emits one question mark,
      // shifting later ASCII cells left despite the raster's two-cell span.
      let raster = RasterSurface(size: .init(width: 4, height: 1), lines: ["👩‍💻XY"])
      #expect(raster.cells[0][0].spanWidth == 2)
      #expect(TerminalSurfaceRenderer(capabilityProfile: .previewASCII).render(raster) == "??XY")
      let output = emission(
        raster, plan: .fullRepaint(surfaceSize: raster.size), profile: .previewASCII
      ).output
      #expect(output == "\u{1B}[2J\u{1B}[1;1H??XY")
    }

    @Test func setA474MetricsCountUTF8AndSyncBytesButAnIdleFrameWritesNothing() throws {
      // Hypothesis: presentation accounting counts graphemes or omits sync
      // delimiters, then emits an empty sync transaction for an unchanged frame.
      let controller = TerminalOutputController()
      var profile = TerminalCapabilityProfile.trueColor
      profile.supportsSynchronizedOutput = true
      let host = host(controller, profile: profile)
      let raster = RasterSurface(size: .init(width: 3, height: 1), lines: ["é界"])
      let initial = try host.present(raster)
      try host.drainPendingPresentation()
      let output = try #require(controller.writes.last)
      #expect(initial.bytesWritten == output.utf8.count)
      #expect(initial.bytesWritten > output.count)
      #expect(initial.usedSynchronizedOutput)
      let count = controller.writes.count
      let idle = try host.present(raster)
      try host.drainPendingPresentation()
      #expect(idle.bytesWritten == 0 && idle.cellsChanged == 0)
      #expect(!idle.usedSynchronizedOutput)
      #expect(controller.writes.count == count)
    }

    @Test func setA475ExplicitTerminalWritesInvalidateTheRetainedDamageBaseline() throws {
      // Hypothesis: a public raw write changes terminal contents but leaves the
      // retained frame trusted, so a subsequent empty damage hint skips repair.
      let controller = TerminalOutputController()
      let host = host(controller)
      let raster = RasterSurface(size: .init(width: 3, height: 1), lines: ["ABC"])
      _ = try host.present(raster)
      try host.drainPendingPresentation()
      try host.write("\u{1B}[1;1HXXX")
      let repaired = try host.present(raster, damage: .init(dirtyRows: []))
      try host.drainPendingPresentation()
      #expect(repaired.usedFullRepaint)
      #expect(controller.writes.last == "\u{1B}[2J\u{1B}[1;1HABC")
    }

    private var close: String { "\u{1B}]8;;\u{1B}\\" }
    private func open(_ destination: String) -> String { "\u{1B}]8;;\(destination)\u{1B}\\" }

    private func surface(_ rows: [[RasterCell]]) -> RasterSurface {
      RasterSurface(
        size: .init(width: rows.map(\.count).max() ?? 0, height: rows.count), cells: rows)
    }

    private func render(_ row: [RasterCell], profile: TerminalCapabilityProfile = .trueColor)
      -> String
    {
      TerminalSurfaceRenderer(capabilityProfile: profile).render(surface([row]))
    }

    private func planner(_ profile: TerminalCapabilityProfile = .trueColor)
      -> TerminalPresentationPlanner
    {
      TerminalPresentationPlanner(capabilityProfile: profile)
    }

    private func emission(
      _ raster: RasterSurface, plan: TerminalPresentationPlan,
      profile: TerminalCapabilityProfile = .trueColor
    ) -> TerminalPresentationEmission {
      var transmitted: Set<UInt32> = []
      var resident: Set<UInt32> = []
      return TerminalHostPresentationEmissionBuilder(
        capabilityProfile: profile, usesTerminalEditOperations: true,
        imageRenderer: TerminalImageRenderer(repository: sharedImageAssetRepository),
        fallbackBackground: .black, terminalBackgroundColor: nil
      ).build(
        for: raster, plan: plan, graphicsCapabilities: .none,
        transmittedKittyImages: &transmitted, residentKittyImageData: &resident)
    }

    private func host(
      _ controller: TerminalOutputController, profile: TerminalCapabilityProfile = .previewUnicode
    ) -> TerminalHost {
      TerminalHost(
        inputFileDescriptor: 0, outputFileDescriptor: 1,
        fallbackSize: .init(width: 20, height: 8), controller: controller,
        capabilityProfile: profile, environment: [:], usesTerminalEditOperations: true)
    }
  }

  private final class TerminalOutputController: TerminalControlling {
    private let storage = LockedBox<[String]>([])
    var writes: [String] { storage.value }
    func isATTY(_: Int32) -> Bool { false }
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot { .init() }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}
    func windowSize(of _: Int32) throws -> CellSize { .init(width: 20, height: 8) }
    func write(_ output: String, to _: Int32) throws { storage.withLock { $0.append(output) } }
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }
#endif
