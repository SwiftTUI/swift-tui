import Testing

@testable import SwiftTUICore

/// D71/B3: rich text is served from ``TextLayoutCache`` like plain text.
///
/// `layoutRichText` used to call the uncached path directly, so every raster of
/// every `.richText` command re-wrapped the payload — and the semantics phase
/// re-wrapped it again to extract link regions. Two full wraps per frame for
/// content that had not changed.
@MainActor
@Suite("Rich text layout cache")
struct RichTextLayoutCacheTests {
  private let options = TextLayoutOptions(
    width: 12,
    lineLimit: nil,
    truncationMode: .tail,
    wrappingStrategy: .wordBoundary
  )

  private func payload(
    _ runs: [(text: String, style: TextStyle, destination: LinkDestination?)]
  ) -> RichTextPayload {
    RichTextPayload(
      runs: runs.map {
        RichTextRun(text: $0.text, style: $0.style, destination: $0.destination)
      }
    )
  }

  @Test("repeating a rich layout request hits the cache")
  func repeatedRichRequestsHitTheCache() {
    let cache = TextLayoutCache(capacity: 8)
    let content = payload([
      ("hello ", .init(), nil),
      ("world", .init(emphasis: .bold), nil),
    ])

    let first = cache.layoutRich(for: content, options: options)
    let second = cache.layoutRich(for: content, options: options)

    #expect(second == first)
    let metrics = cache.metrics
    #expect(metrics.entries == 1)
    #expect(metrics.lookups == 2)
    #expect(metrics.hits == 1)
    #expect(metrics.misses == 1)
  }

  @Test("a steady-state rich repaint performs no further wraps")
  func steadyStateRichRepaintDoesNotRewrap() {
    let cache = TextLayoutCache(capacity: 8)
    let content = payload([("some link text here", .init(), .init("https://x"))])

    _ = cache.layoutRich(for: content, options: options)
    let missesAfterWarmup = cache.metrics.misses

    // Ten repaints of an unchanged payload — the raster and semantics phases
    // both land here.
    for _ in 0..<10 {
      _ = cache.layoutRich(for: content, options: options)
    }

    #expect(cache.metrics.misses == missesAfterWarmup)
    #expect(cache.metrics.hits == 10)
  }

  @Test("payloads differing only in style share one entry and stay correct")
  func richLayoutSharesAnEntryAcrossStyles() {
    // The key is the run *texts*. Clusters carry only character, cell width and
    // a positional `runIndex`, so styling cannot move a wrap point — a link
    // hover restyle must reuse the layout rather than recompute it. If wrapping
    // ever becomes style-sensitive this test fails, which is the point.
    //
    // Both payloads must keep the same run *split*: `RichTextPayload` merges
    // adjacent runs that share a style and destination, so giving one payload
    // two identically-styled runs would collapse it to one run and change
    // `runIndex` — a real layout difference, not a key collision.
    let cache = TextLayoutCache(capacity: 8)
    let styled = payload([
      ("hello ", .init(emphasis: .bold), nil),
      ("world", .init(emphasis: .italic), nil),
    ])
    let restyled = payload([
      ("hello ", .init(emphasis: .italic), nil),
      ("world", .init(underlineStyle: .init(pattern: .single)), .init("https://example.test")),
    ])

    let first = cache.layoutRich(for: styled, options: options)
    let second = cache.layoutRich(for: restyled, options: options)

    #expect(second == first)
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.hits == 1)
    // The layout is still the right one: run indices address the same runs.
    #expect(first.lines.map(\.text) == ["hello world"])
  }

  @Test("a different run split is a different entry")
  func differentRunSplitDoesNotCollide() {
    // Same visible text, different run boundaries: `runIndex` is positional, so
    // the clusters differ and the two layouts must not share an entry.
    let cache = TextLayoutCache(capacity: 8)
    let single = payload([("helloworld", .init(), nil)])
    let split = payload([
      ("hello", .init(emphasis: .bold), nil),
      ("world", .init(), nil),
    ])

    let first = cache.layoutRich(for: single, options: options)
    let second = cache.layoutRich(for: split, options: options)

    #expect(first.lines.map(\.text) == second.lines.map(\.text))
    #expect(cache.metrics.entries == 2)
    #expect(cache.metrics.hits == 0)
    // And the run indices really do differ, which is why they cannot share.
    #expect(first.lines[0].clusters.allSatisfy { cluster in cluster.runIndex == 0 })
    #expect(second.lines[0].clusters.contains { cluster in cluster.runIndex == 1 })
  }

  @Test("rich and plain keys with the same text never collide")
  func richAndPlainKeysAreDisjoint() {
    let cache = TextLayoutCache(capacity: 8)
    _ = cache.layout(for: "hello world", options: options)
    _ = cache.layoutRich(for: payload([("hello world", .init(), nil)]), options: options)

    #expect(cache.metrics.entries == 2)
    #expect(cache.metrics.hits == 0)
  }

  @Test("rich entries participate in eviction and reset")
  func richEntriesEvictAndReset() {
    let cache = TextLayoutCache(capacity: 1)
    let first = payload([("first payload text", .init(), nil)])
    let second = payload([("second payload text", .init(), nil)])

    _ = cache.layoutRich(for: first, options: options)
    #expect(cache.metrics.entries == 1)

    // Over capacity: the second store must be admission-gated exactly like a
    // plain one rather than growing the map.
    _ = cache.layoutRich(for: second, options: options)
    #expect(cache.metrics.entries <= 1)

    cache.reset()
    #expect(cache.metrics.entries == 0)
    #expect(cache.metrics.hits == 0)
    #expect(cache.metrics.lookups == 0)
  }

  @Test("rich layout observes the line limit and truncates like plain text")
  func richLayoutHonorsLineLimit() {
    let cache = TextLayoutCache(capacity: 8)
    let content = payload([("alpha beta gamma delta", .init(), nil)])
    let limited = TextLayoutOptions(
      width: 6,
      lineLimit: 2,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    )

    let layout = cache.layoutRich(for: content, options: limited)
    #expect(layout.lines.count == 2)
    #expect(layout.wasTruncated)
    // Distinct options are a distinct key, so the unlimited layout is separate.
    _ = cache.layoutRich(for: content, options: options)
    #expect(cache.metrics.entries == 2)
  }
}
