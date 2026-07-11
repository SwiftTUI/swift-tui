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
