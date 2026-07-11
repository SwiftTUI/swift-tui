import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI text-content stress behavior", .serialized)
struct FrameworkStressTextContentTests {}

@MainActor
private func textContentRetainedAndFresh<Content: View>(
  renderer: DefaultRenderer,
  rootIdentity: Identity,
  generation: Int,
  proposal: ProposedSize,
  content: Content
) -> (retained: RenderSnapshot, fresh: RenderSnapshot) {
  let retained = renderer.render(
    content,
    context: .init(
      identity: rootIdentity,
      invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
    ),
    proposal: proposal
  )
  let fresh = DefaultRenderer().render(
    content,
    context: .init(identity: rootIdentity),
    proposal: proposal
  )
  return (retained, fresh)
}

private func textContentVisibleWidth(_ line: String) -> Int {
  line.reduce(0) { $0 + cellWidth(of: $1) }
}

// MARK: - Attempt 001: pending separator churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 001 pending separators follow current wrapping")
  func textContent001PendingSeparatorsFollowCurrentWrapping() {
    // Hypothesis: word-boundary wrapping can retain a pending multi-space separator from the
    // previous proposal and replay it at the start of a later retained line.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent001")

    for generation in 0..<24 {
      let width = [6, 9, 7, 10][generation % 4]
      let content = generation.isMultiple(of: 2) ? "AA   BBB CC" : "AA BBB   CC"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.allSatisfy { !$0.hasPrefix(" ") })
    }
  }
}

// MARK: - Attempt 002: edge whitespace exact-fit churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 002 edge whitespace follows exact-fit proposals")
  func textContent002EdgeWhitespaceFollowsExactFitProposals() {
    // Hypothesis: retained wrapping can discard authored leading or trailing whitespace after an
    // exact-fit proposal consumes the same separator run at a different line boundary.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent002")

    for generation in 0..<20 {
      let width = generation.isMultiple(of: 2) ? 6 : 5
      let content = generation.isMultiple(of: 2) ? "  AA BB  " : "   C D "
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.cells[0][0].character == " ")
      #expect(frames.retained.rasterSurface.cells[0][1].character == " ")
      #expect(
        frames.retained.rasterSurface.lines.allSatisfy {
          textContentVisibleWidth($0) <= width
        }
      )
    }
  }
}

// MARK: - Attempt 003: narrow continuation-marker transition

extension FrameworkStressTextContentTests {
  @Test("stress text content 003 narrow word wrapping switches marker strategy")
  func textContent003NarrowWordWrappingSwitchesMarkerStrategy() {
    // Hypothesis: retained long-word layout can replay continuation markers when a width-one or
    // width-two proposal should fall back to unadorned cluster wrapping.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent003")

    for generation in 0..<24 {
      let width = [1, 3, 2, 4][generation % 4]
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text("ABCDEFGHIJ").textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        frames.retained.rasterSurface.lines.joined().contains("–")
          == (width >= 3)
      )
      #expect(
        frames.retained.rasterSurface.lines.allSatisfy {
          textContentVisibleWidth($0) <= width
        }
      )
    }
  }
}

// MARK: - Attempt 004: token-kind replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 004 token replacement removes stale continuation markers")
  func textContent004TokenReplacementRemovesStaleContinuationMarkers() {
    // Hypothesis: retained wrapping can preserve a word-like token's continuation-marker lines
    // after equal-width punctuation changes that token to cluster wrapping.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent004")

    for generation in 0..<20 {
      let wordLike = generation.isMultiple(of: 2)
      let content = wordLike ? "ABCDEFGHIJK" : "AB/CD:EF.GH"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 5, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        frames.retained.rasterSurface.lines.joined().contains("–")
          == wordLike
      )
    }
  }
}

// MARK: - Attempt 005: apostrophe token churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 005 apostrophe tokens keep current continuation topology")
  func textContent005ApostropheTokensKeepCurrentContinuationTopology() {
    // Hypothesis: apostrophe-special-cased word classification can reuse an ASCII token's cached
    // clusters when a curly apostrophe replacement follows the same continuation topology.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent005")

    for generation in 0..<20 {
      let usesCurly = !generation.isMultiple(of: 2)
      let apostrophe = usesCurly ? "’" : "'"
      let content = usesCurly ? "O’BRIENVALUE" : "O'BRIENVALUE"
      let width = generation.isMultiple(of: 3) ? 4 : 5
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.joined().contains(apostrophe))
      #expect(frames.retained.rasterSurface.lines.joined().contains("–"))
    }
  }
}

// MARK: - Attempt 006: zero-width and wide-cluster wrapping

extension FrameworkStressTextContentTests {
  @Test("stress text content 006 zero-width marks do not retain wide-cluster breaks")
  func textContent006ZeroWidthMarksDoNotRetainWideClusterBreaks() {
    // Hypothesis: zero-width format clusters can remain charged to a neighboring wide glyph in
    // retained wrapping after the mark moves to the other side of that glyph.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent006")

    for generation in 0..<20 {
      let content =
        generation.isMultiple(of: 2)
        ? "A\u{200B}界B C"
        : "A界\u{2060}B C"
      let width = generation.isMultiple(of: 3) ? 3 : 4
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        frames.retained.rasterSurface.lines.allSatisfy {
          textContentVisibleWidth($0) <= width
        }
      )
    }
  }
}

// MARK: - Attempt 007: blank-line truncation target

extension FrameworkStressTextContentTests {
  @Test("stress text content 007 blank lines truncate the current visible line")
  func textContent007BlankLinesTruncateCurrentVisibleLine() {
    // Hypothesis: explicit empty lines can shift the retained line-limit truncation indicator onto
    // a formerly visible nonempty line after newline topology churn.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent007")

    for generation in 0..<20 {
      let content = generation.isMultiple(of: 2) ? "AA\n\nCC DD" : "AA BB\n\nCC"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 4, height: nil),
        content: Text(content)
          .lineLimit(2)
          .textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.count == 2)
      #expect(frames.retained.rasterSurface.lines[1].contains("…"))
    }
  }
}

// MARK: - Attempt 008: wide-cluster truncation edges

extension FrameworkStressTextContentTests {
  @Test("stress text content 008 wide-cluster truncation preserves current edges")
  func textContent008WideClusterTruncationPreservesCurrentEdges() {
    // Hypothesis: retained truncation can slice head or middle output using stale scalar-width
    // offsets when two-cell clusters occupy the current edge budget.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent008")
    let modes: [Text.TruncationMode] = [.tail, .head, .middle]
    var observedLines: Set<String> = []

    for generation in 0..<24 {
      let modeIndex = generation % modes.count
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 5, height: nil),
        content: Text("界ABCDE界FG")
          .lineLimit(1)
          .truncationMode(modes[modeIndex])
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      let line = frames.retained.rasterSurface.lines[0]
      observedLines.insert(line)
      #expect(line.contains("…"))
      #expect(textContentVisibleWidth(line) <= 5)
    }

    #expect(observedLines.count == modes.count)
  }
}

// MARK: - Attempt 009: hot-key admission pressure

extension FrameworkStressTextContentTests {
  @Test("stress text content 009 hot unicode layout survives admission churn")
  func textContent009HotUnicodeLayoutSurvivesAdmissionChurn() {
    // Hypothesis: one-shot admission records can evict or alias a repeatedly accessed Unicode
    // layout key while the retained renderer continues revisiting its cell geometry.
    let cache = TextLayoutCache(capacity: 4)
    let options = TextLayoutOptions(width: 5, lineLimit: 2, truncationMode: .middle)
    let hotContent = "界HOTVALUE🙂"
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent009")

    for generation in 0..<32 {
      let cached = cache.layout(for: hotContent, options: options)
      let uncached = uncachedTextLayout(for: hotContent, options: options)
      #expect(cached == uncached)

      _ = cache.layout(
        for: "cold-\(generation)-\(generation.isMultiple(of: 2) ? "界" : "🙂")",
        options: .init(width: 3 + generation % 4, lineLimit: 2)
      )

      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 5, height: nil),
        content: Text(hotContent).lineLimit(2).truncationMode(.middle)
      )
      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(cache.metrics.entries <= 4)
      #expect(cache.accessLogDepth <= 8)
    }

    #expect(cache.metrics.hits >= 31)
    #expect(cache.metrics.bypassedStores > 0)
  }
}

// MARK: - Attempt 010: mixed-width proposal revisit

extension FrameworkStressTextContentTests {
  @Test("stress text content 010 mixed-width proposal revisits match fresh geometry")
  func textContent010MixedWidthProposalRevisitsMatchFreshGeometry() {
    // Hypothesis: retained measurement can reuse an ASCII-derived proposal entry when mixed CJK
    // clusters revisit an older width after intervening wider and narrower layouts.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent010")
    let widths = [4, 9, 6, 3, 6, 9]

    for generation in 0..<30 {
      let width = widths[generation % widths.count]
      let content = generation.isMultiple(of: 2) ? "A界 BC界D E" : "A界B C界 DE"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text(content).textWrappingStrategy(.wordBoundary)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(
        frames.retained.rasterSurface.lines.allSatisfy {
          textContentVisibleWidth($0) <= width
        }
      )
    }
  }
}

// MARK: - Attempt 011: family emoji replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 011 family emoji replacement keeps two-cell geometry")
  func textContent011FamilyEmojiReplacementKeepsTwoCellGeometry() {
    // Hypothesis: retained cell-width metadata can key a multi-scalar ZWJ family by its first
    // emoji scalar and replay the previous grapheme after an equal-width family replacement.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent011")

    for generation in 0..<20 {
      let emoji = generation.isMultiple(of: 2) ? "👨‍👩‍👧‍👦" : "👩‍👩‍👦‍👦"
      let width = generation.isMultiple(of: 3) ? 4 : 5
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text("A\(emoji)B C")
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.joined().contains(emoji))
      #expect(emoji.first.map { cellWidth(of: $0) } == 2)
    }
  }
}

// MARK: - Attempt 012: regional-indicator replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 012 flag replacement keeps two-cell geometry")
  func textContent012FlagReplacementKeepsTwoCellGeometry() {
    // Hypothesis: a retained regional-indicator pair can be mistaken for two scalar cells or can
    // preserve the prior flag payload when another two-cell flag occupies the same slot.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent012")

    for generation in 0..<20 {
      let flag = generation.isMultiple(of: 2) ? "🇺🇸" : "🇯🇵"
      let width = generation.isMultiple(of: 3) ? 4 : 5
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: width, height: nil),
        content: Text("A\(flag)BC D")
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.joined().contains(flag))
      #expect(flag.first.map { cellWidth(of: $0) } == 2)
    }
  }
}

// MARK: - Attempt 013: keycap variation-selector replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 013 keycap replacement updates width and wrapping")
  func textContent013KeycapReplacementUpdatesWidthAndWrapping() {
    // Hypothesis: retained text width can ignore VS16 and enclosing-keycap scalars when the base
    // digit is unchanged, preserving the plain digit's one-cell wrapping geometry.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent013")

    for generation in 0..<20 {
      let keycap = generation.isMultiple(of: 2) ? "1️⃣" : "1"
      let expectedWidth = generation.isMultiple(of: 2) ? 2 : 1
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 4, height: nil),
        content: Text("A\(keycap)BC")
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.joined().contains(keycap))
      #expect(keycap.first.map { cellWidth(of: $0) } == expectedWidth)
      #expect(frames.retained.measuredTree.measuredSize.height == (expectedWidth == 2 ? 2 : 1))
    }
  }
}

// MARK: - Attempt 014: leading zero-width cluster placement

extension FrameworkStressTextContentTests {
  @Test("stress text content 014 leading zero-width clusters preserve visible placement")
  func textContent014LeadingZeroWidthClustersPreserveVisiblePlacement() {
    // Hypothesis: a retained leading zero-width combining or format cluster can advance the draw
    // cursor even though fresh measurement assigns it no terminal cells.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent014")

    for generation in 0..<20 {
      let content = generation.isMultiple(of: 2) ? "\u{0301}AB" : "\u{2060}AB"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 2, height: nil),
        content: Text(content)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == .init(width: 2, height: 1))
      #expect(frames.retained.rasterSurface.lines == ["AB"])
    }
  }
}

// MARK: - Attempt 015: bidi-control cell geometry

extension FrameworkStressTextContentTests {
  @Test("stress text content 015 bidi controls consume no retained cells")
  func textContent015BidiControlsConsumeNoRetainedCells() {
    // Hypothesis: embedding and isolate controls can retain a positive cell span when their
    // zero-width cluster topology changes around the same right-to-left payload.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TextContent015")

    for generation in 0..<20 {
      let content =
        generation.isMultiple(of: 2)
        ? "A\u{2067}אב\u{2069}B"
        : "A\u{202B}אב\u{202C}B"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 4, height: nil),
        content: Text(content)
      )

      #expect(frames.retained.measuredTree.measuredSize == frames.fresh.measuredTree.measuredSize)
      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.measuredTree.measuredSize == .init(width: 4, height: 1))
      #expect(frames.retained.rasterSurface.lines == ["AאבB"])
    }
  }
}

// MARK: - Attempt 016: terminal-control presentation churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 016 control scalars stay sanitized across presentations")
  func textContent016ControlScalarsStaySanitizedAcrossPresentations() {
    // Hypothesis: retained raster cells or terminal presentation state can replay an unsanitized
    // C0, C1, or escape scalar after the authored control kind changes in place.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent016")
    let controls: [Character] = ["\u{001B}", "\u{0007}", "\u{009B}"]

    for generation in 0..<24 {
      let control = controls[generation % controls.count]
      let content = "A\(control)B"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 3, height: 1),
        content: Text(content)
      )
      let presented = terminalRenderer.render(frames.retained.rasterSurface)

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(presented.contains("A�B"))
      #expect(!presented.contains("A\(control)B"))
      #expect(frames.retained.semanticSnapshot.focusRegions.isEmpty)
      #expect(frames.retained.semanticSnapshot.interactionRegions.isEmpty)
    }
  }
}

// MARK: - Attempt 017: OSC-8 destination sanitization churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 017 hyperlink destinations sanitize every replacement")
  func textContent017HyperlinkDestinationsSanitizeEveryReplacement() {
    // Hypothesis: retained hyperlink cells or terminal OSC-8 state can reuse a previously
    // sanitized destination and let controls from the current destination cross the boundary.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent017")

    for generation in 0..<20 {
      let first = generation.isMultiple(of: 2)
      let rawDestination =
        first
        ? "https://safe.example/\u{001B}\\\u{0007}one"
        : "https://safe.example/\u{009B}\u{001B}\\two"
      let safeDestination = first ? "https://safe.example/one" : "https://safe.example/two"
      let content = Text("Go \(Link("Docs", destination: .init(rawDestination)))")
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 7, height: 1),
        content: content
      )
      let presented = terminalRenderer.render(frames.retained.rasterSurface)
      let rasterHyperlinks = Set(
        frames.retained.rasterSurface.cells.flatMap { row in
          row.compactMap(\.hyperlink)
        })

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(rasterHyperlinks == [rawDestination])
      #expect(frames.retained.semanticSnapshot.focusRegions.count == 1)
      #expect(frames.retained.semanticSnapshot.interactionRegions.count == 1)
      #expect(presented.contains("\u{001B}]8;;\(safeDestination)\u{001B}\\"))
      #expect(!presented.contains(rawDestination))
    }
  }
}

// MARK: - Attempt 018: equal-width emoji payload replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 018 emoji modifier replacement publishes current grapheme")
  func textContent018EmojiModifierReplacementPublishesCurrentGrapheme() {
    // Hypothesis: retained raster substitution can treat two equal-width emoji-modifier sequences
    // as the same draw payload and keep the previous skin-tone bytes.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent018")

    for generation in 0..<20 {
      let emoji = generation.isMultiple(of: 2) ? "👋🏻" : "👋🏿"
      let otherEmoji = generation.isMultiple(of: 2) ? "👋🏿" : "👋🏻"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 4, height: 1),
        content: Text("A\(emoji)B")
      )
      let presented = terminalRenderer.render(frames.retained.rasterSurface)

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.rasterSurface.lines.joined().contains(emoji))
      #expect(!frames.retained.rasterSurface.lines.joined().contains(otherEmoji))
      #expect(presented.contains(emoji))
      #expect(frames.retained.semanticSnapshot.focusRegions.isEmpty)
      #expect(frames.retained.semanticSnapshot.interactionRegions.isEmpty)
    }
  }
}

// MARK: - Attempt 019: rich-run split and merge

extension FrameworkStressTextContentTests {
  @Test("stress text content 019 rich runs publish current normalized topology")
  func textContent019RichRunsPublishCurrentNormalizedTopology() {
    // Hypothesis: retained rich-text extraction can preserve a prior normalized run partition when
    // equal visible text alternates between merged and locally styled fragments.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .previewUnicode)
    let rootIdentity = testIdentity("TextContent019")

    for generation in 0..<20 {
      let isSplit = generation.isMultiple(of: 2)
      let content =
        isSplit
        ? Text("A\(Text("B").bold())C")
        : Text("A\(Text("B"))C")
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 3, height: 1),
        content: content
      )

      guard case .richText(let payload) = frames.retained.resolvedTree.drawPayload else {
        Issue.record("Expected retained rich-text payload")
        continue
      }

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(payload.visibleText == "ABC")
      #expect(payload.runs.count == (isSplit ? 3 : 1))
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains("ABC"))
      #expect(frames.retained.semanticSnapshot.focusRegions.isEmpty)
      #expect(frames.retained.semanticSnapshot.interactionRegions.isEmpty)
    }
  }
}

// MARK: - Attempt 020: same-label link destination replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 020 same-label link updates every hyperlink cell")
  func textContent020SameLabelLinkUpdatesEveryHyperlinkCell() {
    // Hypothesis: retained rich-text draw equality can key an inline link by visible label and
    // preserve the first destination across same-label replacements.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent020")
    let linkIdentity = testIdentity("TextContent020", "InlineLink[0]")

    for generation in 0..<20 {
      let current = generation.isMultiple(of: 2) ? "https://one.example" : "https://two.example"
      let departed = generation.isMultiple(of: 2) ? "https://two.example" : "https://one.example"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 7, height: 1),
        content: Text("Go \(Link("Docs", destination: .init(current)))")
      )
      let hyperlinkCells = frames.retained.rasterSurface.cells.flatMap { row in
        row.filter { $0.hyperlink != nil }
      }
      let presented = terminalRenderer.render(frames.retained.rasterSurface)

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(hyperlinkCells.count == 4)
      #expect(hyperlinkCells.allSatisfy { $0.hyperlink == current })
      #expect(frames.retained.semanticSnapshot.focusRegions.map(\.identity) == [linkIdentity])
      #expect(frames.retained.semanticSnapshot.interactionRegions.map(\.identity) == [linkIdentity])
      #expect(presented.contains(current))
      #expect(!presented.contains(departed))
    }
  }
}

// MARK: - Attempt 021: inline-link geometry churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 021 inline-link label churn updates semantic geometry")
  func textContent021InlineLinkLabelChurnUpdatesSemanticGeometry() {
    // Hypothesis: inline-link focus and interaction fragments can retain the short label's one-line
    // bounds when the same link identity expands across multiple wrapped lines.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent021")
    let destination = "https://geometry.example"

    for generation in 0..<20 {
      let isLong = generation.isMultiple(of: 2)
      let label = isLong ? "BETA LONG" : "B"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 6, height: nil),
        content: Text("A \(Link(label, destination: .init(destination))) Z")
      )
      let linkCells = frames.retained.rasterSurface.cells.flatMap { row in
        row.filter { $0.hyperlink == destination }
      }

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(frames.retained.semanticSnapshot.focusRegions.count == 1)
      #expect(frames.retained.semanticSnapshot.interactionRegions.count == (isLong ? 2 : 1))
      #expect(linkCells.count == (isLong ? 8 : 1))
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains(destination))
      if isLong {
        #expect(frames.retained.semanticSnapshot.focusRegions[0].rect.size.height == 2)
      } else {
        #expect(frames.retained.semanticSnapshot.focusRegions[0].rect.size.height == 1)
      }
    }
  }
}

// MARK: - Attempt 022: adjacent same-destination link identities

extension FrameworkStressTextContentTests {
  @Test("stress text content 022 adjacent links keep distinct semantic identities")
  func textContent022AdjacentLinksKeepDistinctSemanticIdentities() {
    // Hypothesis: rich-run normalization can merge adjacent links that share a destination and
    // style, collapsing their retained inline identities after separator or cardinality churn.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent022")
    let destination = "https://shared.example"

    for generation in 0..<20 {
      let hasThird = generation.isMultiple(of: 2)
      let content =
        hasThird
        ? Text(
          "\(Link("A", destination: .init(destination)))-\(Link("B", destination: .init(destination))) \(Link("C", destination: .init(destination)))"
        )
        : Text(
          "\(Link("A", destination: .init(destination)))\(Link("B", destination: .init(destination)))"
        )
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 6, height: 1),
        content: content
      )
      let expectedCount = hasThird ? 3 : 2
      let expectedIdentities = (0..<expectedCount).map {
        testIdentity("TextContent022", "InlineLink[\($0)]")
      }
      let hyperlinkCells = frames.retained.rasterSurface.cells.flatMap { row in
        row.filter { $0.hyperlink == destination }
      }

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(frames.retained.semanticSnapshot.focusRegions.map(\.identity) == expectedIdentities)
      #expect(
        frames.retained.semanticSnapshot.interactionRegions.map(\.identity) == expectedIdentities
      )
      #expect(hyperlinkCells.count == expectedCount)
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains(destination))
    }
  }
}

// MARK: - Attempt 023: inline-link explicit-line movement

extension FrameworkStressTextContentTests {
  @Test("stress text content 023 inline-link semantics follow explicit newlines")
  func textContent023InlineLinkSemanticsFollowExplicitNewlines() {
    // Hypothesis: retained rich-text semantics can keep an inline link on its former explicit line
    // when the same payload moves above or below a newline without changing width.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent023")
    let destination = "https://line.example"

    for generation in 0..<20 {
      let linkOnSecondLine = generation.isMultiple(of: 2)
      let link = Link("LINK", destination: .init(destination))
      let content = linkOnSecondLine ? Text("A\n\(link)") : Text("\(link)\nA")
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 4, height: 2),
        content: content
      )
      let expectedY = linkOnSecondLine ? 1 : 0
      let focusRegion = frames.retained.semanticSnapshot.focusRegions.first
      let interactionRegion = frames.retained.semanticSnapshot.interactionRegions.first
      let hyperlinkCells = frames.retained.rasterSurface.cells.flatMap { row in
        row.filter { $0.hyperlink == destination }
      }

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(focusRegion?.rect.origin == .init(x: 0, y: expectedY))
      #expect(interactionRegion?.rect.origin == .init(x: 0, y: expectedY))
      #expect(hyperlinkCells.count == 4)
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains(destination))
    }
  }
}

// MARK: - Attempt 024: truncated inline-link semantics

extension FrameworkStressTextContentTests {
  @Test("stress text content 024 truncated link excludes hidden and ellipsis cells")
  func textContent024TruncatedLinkExcludesHiddenAndEllipsisCells() {
    // Hypothesis: rich-text truncation can carry an inline link's run index onto the synthetic
    // ellipsis or preserve semantic width for hidden suffix clusters.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent024")
    let destination = "https://truncated.example"

    for generation in 0..<20 {
      let label = generation.isMultiple(of: 2) ? "ABCDEFGHIJ" : "ABCDKLMNOP"
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 5, height: 1),
        content: Text("\(Link(label, destination: .init(destination)))")
          .lineLimit(1)
          .truncationMode(.tail)
      )
      let cells = frames.retained.rasterSurface.cells[0]
      let focusRegion = frames.retained.semanticSnapshot.focusRegions.first
      let interactionRegion = frames.retained.semanticSnapshot.interactionRegions.first

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(frames.retained.rasterSurface.lines == ["ABCD…"])
      #expect(cells.prefix(4).allSatisfy { $0.hyperlink == destination })
      #expect(cells[4].character == "…")
      #expect(cells[4].hyperlink == nil)
      #expect(focusRegion?.rect.size == .init(width: 4, height: 1))
      #expect(interactionRegion?.rect.size == .init(width: 4, height: 1))
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains(destination))
    }
  }
}

// MARK: - Attempt 025: nested rich-style inheritance churn

extension FrameworkStressTextContentTests {
  @Test("stress text content 025 nested link styles follow current inheritance")
  func textContent025NestedLinkStylesFollowCurrentInheritance() {
    // Hypothesis: retained rich-run merging can combine the current link-local emphasis with the
    // previous outer foreground instead of rebuilding both style layers together.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let terminalRenderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let rootIdentity = testIdentity("TextContent025")
    let destination = "https://style.example"

    for generation in 0..<20 {
      let isBold = generation.isMultiple(of: 2)
      let content =
        isBold
        ? Text(
          "A \(Link(Text("L").bold(), destination: .init(destination))) Z"
        ).foregroundStyle(.red)
        : Text(
          "A \(Link(Text("L").italic(), destination: .init(destination))) Z"
        ).foregroundStyle(.blue)
      let frames = textContentRetainedAndFresh(
        renderer: renderer,
        rootIdentity: rootIdentity,
        generation: generation,
        proposal: .init(width: 5, height: 1),
        content: content
      )
      let cells = frames.retained.rasterSurface.cells[0]
      let outerStyle = cells[0].style
      let linkStyle = cells[2].style

      #expect(frames.retained.rasterSurface == frames.fresh.rasterSurface)
      #expect(frames.retained.semanticSnapshot == frames.fresh.semanticSnapshot)
      #expect(outerStyle?.foregroundColor == (isBold ? .red : .blue))
      #expect(linkStyle?.emphasis.contains(.bold) == isBold)
      #expect(linkStyle?.emphasis.contains(.italic) == !isBold)
      #expect(cells[2].hyperlink == destination)
      #expect(frames.retained.semanticSnapshot.focusRegions.count == 1)
      #expect(frames.retained.semanticSnapshot.interactionRegions.count == 1)
      #expect(terminalRenderer.render(frames.retained.rasterSurface).contains(destination))
    }
  }
}

@MainActor
private final class TextContentBox<Value> {
  var value: Value
  var writeCount = 0

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writeCount += 1
      }
    )
  }
}

// MARK: - Attempt 026: same-binding external replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 026 focused field edits live external replacement")
  func textContent026FocusedFieldEditsLiveExternalReplacement() throws {
    // Hypothesis: a focused TextField can keep editing its internal pre-replacement string after
    // the same binding receives equal-length external content at a retained identity.
    let text = TextContentBox("abcd")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent026Root"),
      size: .init(width: 32, height: 4)
    ) {
      TextContent026Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent026Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.clickText("Replace same length")
    _ = try harness.focus(TextContent026Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.value == "WX!YZ")
    #expect(text.writeCount == 1)
    #expect(harness.frame.contains("WX!YZ"))
  }
}

@MainActor
private struct TextContent026Fixture: View {
  static let fieldIdentity = testIdentity("TextContent026", "Field")

  let text: TextContentBox<String>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace same length") { text.value = "WXYZ" }
      TextField("Value", text: text.binding())
        .id(Self.fieldIdentity)
        .textFieldStyle(.plain)
    }
  }
}

// MARK: - Attempt 027: shorter external replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 027 focused field clamps caret after shortening")
  func textContent027FocusedFieldClampsCaretAfterShortening() throws {
    // Hypothesis: a retained TextField can preserve an out-of-range caret after external
    // shortening and then insert into stale content or at the old offset.
    let text = TextContentBox("abcdefgh")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent027Root"),
      size: .init(width: 32, height: 4)
    ) {
      TextContent027Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent027Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.clickText("Replace with short text")
    _ = try harness.focus(TextContent027Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.value == "xy!")
    #expect(text.writeCount == 1)
    #expect(harness.frame.contains("xy!"))
  }
}

@MainActor
private struct TextContent027Fixture: View {
  static let fieldIdentity = testIdentity("TextContent027", "Field")

  let text: TextContentBox<String>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace with short text") { text.value = "xy" }
      TextField("Value", text: text.binding())
        .id(Self.fieldIdentity)
        .textFieldStyle(.plain)
    }
  }
}

// MARK: - Attempt 028: single-line Unicode paste sanitization

extension FrameworkStressTextContentTests {
  @Test("stress text content 028 field paste filters newlines around graphemes")
  func textContent028FieldPasteFiltersNewlinesAroundGraphemes() throws {
    // Hypothesis: single-line paste sanitization can split extended graphemes or leave a carriage
    // return when removing mixed CR, LF, and CRLF sequences at a moved caret.
    let text = TextContentBox("A👨‍👩‍👧‍👦B")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent028Root"),
      size: .init(width: 40, height: 3)
    ) {
      TextContent028Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent028Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.paste("X\r\n👋🏿\nY\rZ")

    #expect(text.writeCount == 1)
    let expected = "A👨‍👩‍👧‍👦X👋🏿YZB"
    let isSanitized =
      text.value == expected
      && !text.value.unicodeScalars.contains { $0.value == 0x0A || $0.value == 0x0D }
      && harness.frame.contains(expected)
    withKnownIssue("Single-line paste preserves CRLF as one extended grapheme cluster") {
      #expect(isSanitized)
    }
  }
}

@MainActor
private struct TextContent028Fixture: View {
  static let fieldIdentity = testIdentity("TextContent028", "Field")

  let text: TextContentBox<String>

  var body: some View {
    TextField("Value", text: text.binding())
      .id(Self.fieldIdentity)
      .textFieldStyle(.plain)
  }
}

// MARK: - Attempt 029: secure external replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 029 secure field remasks external replacement")
  func textContent029SecureFieldRemasksExternalReplacement() throws {
    // Hypothesis: a focused SecureField can preserve old mask length or stale plaintext/caret state
    // when its bound value is externally replaced at the same retained identity.
    let text = TextContentBox("secret")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent029Root"),
      size: .init(width: 34, height: 4)
    ) {
      TextContent029Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent029Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    _ = try harness.clickText("Replace secure value")
    _ = try harness.focus(TextContent029Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.value == "alph!abet")
    #expect(text.writeCount == 1)
    #expect(harness.frame.contains(String(repeating: "•", count: text.value.count)))
    #expect(!harness.frame.contains("secret"))
    #expect(!harness.frame.contains("alphabet"))
    #expect(!harness.frame.contains("alph!abet"))
  }
}

@MainActor
private struct TextContent029Fixture: View {
  static let fieldIdentity = testIdentity("TextContent029", "Field")

  let text: TextContentBox<String>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace secure value") { text.value = "alphabet" }
      SecureField("Secret", text: text.binding())
        .id(Self.fieldIdentity)
        .textFieldStyle(.plain)
    }
  }
}

// MARK: - Attempt 030: secure grapheme selection replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 030 secure select-all replaces graphemes once")
  func textContent030SecureSelectAllReplacesGraphemesOnce() throws {
    // Hypothesis: secure projection can make select-all replacement count masked cells instead of
    // source grapheme clusters, causing partial deletion or duplicate binding writes.
    let text = TextContentBox("A👨‍👩‍👧‍👦界")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent030Root"),
      size: .init(width: 28, height: 3)
    ) {
      TextContent030Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent030Fixture.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.character("a"), modifiers: .ctrl))
    _ = try harness.paste("👋🏿Z")

    #expect(text.value == "👋🏿Z")
    #expect(text.writeCount == 1)
    #expect(harness.frame.contains("••"))
    #expect(!harness.frame.contains("👨‍👩‍👧‍👦"))
    #expect(!harness.frame.contains("👋🏿"))
    #expect(!harness.frame.contains("界"))
  }
}

@MainActor
private struct TextContent030Fixture: View {
  static let fieldIdentity = testIdentity("TextContent030", "Field")

  let text: TextContentBox<String>

  var body: some View {
    SecureField("Secret", text: text.binding())
      .id(Self.fieldIdentity)
      .textFieldStyle(.plain)
  }
}

// MARK: - Attempt 031: visual-wrap vertical movement

extension FrameworkStressTextContentTests {
  @Test("stress text content 031 editor vertical movement follows visual wrapping")
  func textContent031EditorVerticalMovementFollowsVisualWrapping() throws {
    // Hypothesis: TextEditor computes Up and Down against an unbounded layout map, so a visually
    // wrapped line behaves as one logical line and leaves the caret at the document end.
    let text = TextContentBox("ABCDEFGHIJKL")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent031Root"),
      size: .init(width: 12, height: 6)
    ) {
      TextContent031Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent031Fixture.editorIdentity)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.writeCount == 1)
    withKnownIssue("TextEditor vertical movement ignores its rendered wrapping width") {
      #expect(text.value == "ABCDEFG!HIJKL")
    }
  }
}

@MainActor
private struct TextContent031Fixture: View {
  static let editorIdentity = testIdentity("TextContent031", "Editor")

  let text: TextContentBox<String>

  var body: some View {
    TextEditor(text: text.binding())
      .id(Self.editorIdentity)
      .frame(width: 7, height: 5, alignment: .topLeading)
  }
}

// MARK: - Attempt 032: multiline external replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 032 editor edits live shortened multiline binding")
  func textContent032EditorEditsLiveShortenedMultilineBinding() throws {
    // Hypothesis: TextEditor can retain its old multiline buffer and moved caret after an external
    // shortening, causing the next edit to resurrect departed lines or write past the live value.
    let text = TextContentBox("alpha\nbravo\ncharlie")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent032Root"),
      size: .init(width: 34, height: 8)
    ) {
      TextContent032Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent032Fixture.editorIdentity)
    _ = try harness.pressKey(KeyPress(.home))
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.pressKey(KeyPress(.arrowRight))
    _ = try harness.clickText("Replace editor text")
    _ = try harness.focus(TextContent032Fixture.editorIdentity)
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.value == "one\ntwo!")
    #expect(text.writeCount == 1)
    #expect(harness.frame.contains("two!"))
    #expect(!harness.frame.contains("charlie"))
  }
}

@MainActor
private struct TextContent032Fixture: View {
  static let editorIdentity = testIdentity("TextContent032", "Editor")

  let text: TextContentBox<String>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace editor text") { text.value = "one\ntwo" }
      TextEditor(text: text.binding())
        .id(Self.editorIdentity)
        .frame(width: 18, height: 5, alignment: .topLeading)
    }
  }
}

// MARK: - Attempt 033: cross-newline selection replacement

extension FrameworkStressTextContentTests {
  @Test("stress text content 033 editor replacement clears cross-line selection")
  func textContent033EditorReplacementClearsCrossLineSelection() throws {
    // Hypothesis: replacing a reverse-direction TextEditor selection that crosses a newline can
    // leave the old anchor active, so the following character replaces current content again.
    let text = TextContentBox("ab\ncd")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TextContent033Root"),
      size: .init(width: 24, height: 6)
    ) {
      TextContent033Fixture(text: text)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(TextContent033Fixture.editorIdentity)
    _ = try harness.pressKey(KeyPress(.home, modifiers: .shift))
    _ = try harness.pressKey(KeyPress(.arrowLeft, modifiers: .shift))
    _ = try harness.paste("👋🏿\nQ")
    _ = try harness.pressKey(KeyPress(.character("!")))

    #expect(text.value == "ab👋🏿\nQ!")
    #expect(text.writeCount == 2)
    #expect(harness.frame.contains("ab👋🏿"))
    #expect(harness.frame.contains("Q!"))
    #expect(!harness.frame.contains("cd"))
  }
}

@MainActor
private struct TextContent033Fixture: View {
  static let editorIdentity = testIdentity("TextContent033", "Editor")

  let text: TextContentBox<String>

  var body: some View {
    TextEditor(text: text.binding())
      .id(Self.editorIdentity)
      .frame(width: 18, height: 5, alignment: .topLeading)
  }
}
