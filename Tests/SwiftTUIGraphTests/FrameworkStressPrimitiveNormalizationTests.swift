import Testing

@testable import SwiftTUIGraph

@Suite("Framework stress: primitive normalization", .serialized)
struct FrameworkStressPrimitiveNormalizationTests {
  @Test("stress primitive normalization 001 empty rich-text runs disappear")
  func primitiveNormalization001EmptyRichTextRunsDisappear() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: ""),
      RichTextRun(text: "visible"),
      RichTextRun(text: ""),
    ])

    #expect(payload.runs.count == 1)
    #expect(payload.runs[0].text == "visible")
  }

  @Test("stress primitive normalization 002 empty seams do not prevent merging")
  func primitiveNormalization002EmptySeamsDoNotPreventMerging() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "left"),
      RichTextRun(text: ""),
      RichTextRun(text: "right"),
    ])

    #expect(payload.runs.count == 1)
    #expect(payload.runs[0].text == "leftright")
  }

  @Test("stress primitive normalization 003 destinations remain a merge boundary")
  func primitiveNormalization003DestinationsRemainAMergeBoundary() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "same", destination: "https://one.example"),
      RichTextRun(text: "label", destination: "https://two.example"),
    ])

    #expect(payload.runs.count == 2)
    #expect(payload.visibleText == "samelabel")
  }

  @Test("stress primitive normalization 004 link identities remain a merge boundary")
  func primitiveNormalization004LinkIdentitiesRemainAMergeBoundary() {
    let destination: LinkDestination = "https://same.example"
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "one", destination: destination, linkIdentifier: "link-1"),
      RichTextRun(text: "two", destination: destination, linkIdentifier: "link-2"),
    ])

    #expect(payload.runs.count == 2)
    #expect(payload.linkCount == 2)
  }

  @Test("stress primitive normalization 005 style changes remain a merge boundary")
  func primitiveNormalization005StyleChangesRemainAMergeBoundary() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "plain"),
      RichTextRun(text: "bold", style: TextStyle(emphasis: .bold)),
    ])

    #expect(payload.runs.count == 2)
    #expect(payload.runs.map(\.style.emphasis) == [[], .bold])
  }

  @Test("stress primitive normalization 006 nonadjacent link identities stay distinct")
  func primitiveNormalization006NonadjacentLinkIdentitiesStayDistinct() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "one", linkIdentifier: "first"),
      RichTextRun(text: "gap"),
      RichTextRun(text: "two", linkIdentifier: "second"),
    ])

    #expect(payload.linkCount == 2)
  }

  @Test("stress primitive normalization 007 repeated nonadjacent link identity counts once")
  func primitiveNormalization007RepeatedNonadjacentLinkIdentityCountsOnce() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "one", linkIdentifier: "shared"),
      RichTextRun(text: "gap", style: TextStyle(emphasis: .italic)),
      RichTextRun(text: "two", linkIdentifier: "shared"),
    ])

    #expect(payload.runs.count == 3)
    #expect(payload.linkCount == 1)
  }

  @Test("stress primitive normalization 008 visible text preserves Unicode run order")
  func primitiveNormalization008VisibleTextPreservesUnicodeRunOrder() {
    let payload = RichTextPayload(runs: [
      RichTextRun(text: "e\u{301}"),
      RichTextRun(text: "👩🏽‍💻", style: TextStyle(emphasis: .bold)),
      RichTextRun(text: "漢"),
    ])

    #expect(payload.visibleText == "e\u{301}👩🏽‍💻漢")
    #expect(Array(payload.visibleText).count == 3)
  }

  @Test("stress primitive normalization 009 normalization is idempotent")
  func primitiveNormalization009NormalizationIsIdempotent() {
    let initial = RichTextPayload(runs: [
      RichTextRun(text: "A"),
      RichTextRun(text: ""),
      RichTextRun(text: "B"),
      RichTextRun(text: "C", style: TextStyle(emphasis: .bold)),
    ])
    let normalizedAgain = RichTextPayload(runs: initial.runs)

    #expect(normalizedAgain == initial)
    #expect(normalizedAgain.runs.map(\.text) == ["AB", "C"])
  }

  @Test("stress primitive normalization 010 merging retains an unchallenged foreground")
  func primitiveNormalization010MergingRetainsAnUnchallengedForeground() {
    let base = TextStyle(foregroundStyle: AnyShapeStyle(Color.red), emphasis: .bold)
    let overlay = TextStyle(emphasis: .italic)
    let merged = base.merging(overlay)

    #expect(merged.foregroundStyle == AnyShapeStyle(Color.red))
    #expect(merged.emphasis == TextStyle.TextEmphasis([.bold, .italic]))
  }

  @Test("stress primitive normalization 011 explicit opacity overrides while absence preserves")
  func primitiveNormalization011ExplicitOpacityOverridesWhileAbsencePreserves() {
    let base = TextStyle(opacity: 0.25)
    let preserved = base.merging(TextStyle(emphasis: .faint))
    let overridden = preserved.merging(TextStyle(opacity: 0.75))

    #expect(preserved.explicitOpacity == 0.25)
    #expect(overridden.explicitOpacity == 0.75)
  }

  @Test("stress primitive normalization 012 merging unions every emphasis bit")
  func primitiveNormalization012MergingUnionsEveryEmphasisBit() {
    let first = TextStyle(emphasis: [.bold, .faint, .reverse])
    let second = TextStyle(emphasis: [.italic, .blink])
    let merged = first.merging(second)

    #expect(merged.emphasis == [.bold, .italic, .faint, .blink, .reverse])
  }

  @Test("stress primitive normalization 013 line decorations merge independently")
  func primitiveNormalization013LineDecorationsMergeIndependently() {
    let underline = TextLineStyle(pattern: .double, color: .blue)
    let strike = TextLineStyle(pattern: .dashDot, color: .yellow)
    let base = TextStyle(
      backgroundStyle: AnyShapeStyle(Color.black), underlineStyle: underline)
    let merged = base.merging(TextStyle(strikethroughStyle: strike))

    #expect(merged.backgroundStyle == AnyShapeStyle(Color.black))
    #expect(merged.underlineStyle == underline)
    #expect(merged.strikethroughStyle == strike)
  }
}
