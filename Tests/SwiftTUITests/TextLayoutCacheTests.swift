import Testing

@testable import SwiftTUICore

@MainActor
@Suite
struct TextLayoutCacheTests {
  @Test("identical layout requests hit the cache")
  func identicalRequestsHitTheCache() {
    let cache = TextLayoutCache(capacity: 8)
    let options = TextLayoutOptions(
      width: 5,
      lineLimit: 1,
      truncationMode: .tail,
      wrappingStrategy: .wordBoundary
    )

    let first = cache.layout(
      for: "alpha beta gamma",
      options: options
    )
    let second = cache.layout(
      for: "alpha beta gamma",
      options: options
    )

    #expect(first.lines.map(\.text) == ["alph…"])
    #expect(second == first)

    let metrics = cache.metrics
    #expect(metrics.entries == 1)
    #expect(metrics.lookups == 2)
    #expect(metrics.hits == 1)
    #expect(metrics.misses == 1)
    #expect(metrics.stores == 1)
    #expect(metrics.evictions == 0)
  }

  @Test("layout requests stay distinct across widths and truncation modes")
  func distinctWidthsAndTruncationModesStaySeparate() {
    let cache = TextLayoutCache(capacity: 8)

    let wrapped = cache.layout(
      for: "alpha beta",
      options: .init(width: 5)
    )
    let unwrapped = cache.layout(
      for: "alpha beta",
      options: .init(width: nil)
    )
    let tailTruncated = cache.layout(
      for: "alpha beta gamma",
      options: .init(width: 5, lineLimit: 1, truncationMode: .tail)
    )
    let headTruncated = cache.layout(
      for: "alpha beta gamma",
      options: .init(width: 5, lineLimit: 1, truncationMode: .head)
    )
    let middleTruncated = cache.layout(
      for: "alpha beta gamma",
      options: .init(width: 5, lineLimit: 1, truncationMode: .middle)
    )
    let tailTruncatedAgain = cache.layout(
      for: "alpha beta gamma",
      options: .init(width: 5, lineLimit: 1, truncationMode: .tail)
    )

    #expect(wrapped.lines.map(\.text) == ["alpha", "beta"])
    #expect(unwrapped.lines.map(\.text) == ["alpha beta"])
    #expect(tailTruncated.lines.map(\.text) == ["alph…"])
    #expect(headTruncated.lines.map(\.text) == ["…lpha"])
    #expect(middleTruncated.lines.map(\.text) == ["al…ha"])
    #expect(tailTruncatedAgain == tailTruncated)

    let metrics = cache.metrics
    #expect(metrics.entries == 5)
    #expect(metrics.lookups == 6)
    #expect(metrics.hits == 1)
    #expect(metrics.misses == 5)
    #expect(metrics.stores == 5)
    #expect(metrics.evictions == 0)
  }

  @Test("cache eviction keeps the most recently used entry")
  func evictionKeepsMostRecentlyUsedEntry() {
    let cache = TextLayoutCache(capacity: 2)
    let options = TextLayoutOptions(width: nil)

    let firstAlpha = cache.layout(for: "alpha", options: options)
    let firstBeta = cache.layout(for: "beta", options: options)
    let refreshedAlpha = cache.layout(for: "alpha", options: options)
    _ = cache.layout(for: "gamma", options: options)
    let retainedAlpha = cache.layout(for: "alpha", options: options)
    let reloadedBeta = cache.layout(for: "beta", options: options)

    #expect(refreshedAlpha == firstAlpha)
    #expect(retainedAlpha == firstAlpha)
    #expect(reloadedBeta == firstBeta)

    let metrics = cache.metrics
    #expect(metrics.entries == 2)
    #expect(metrics.lookups == 6)
    #expect(metrics.hits == 2)
    #expect(metrics.misses == 4)
    #expect(metrics.stores == 4)
    #expect(metrics.evictions == 2)
  }
}
