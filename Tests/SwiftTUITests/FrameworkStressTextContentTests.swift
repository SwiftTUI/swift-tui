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
