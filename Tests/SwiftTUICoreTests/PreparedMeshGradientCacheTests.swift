import Testing

@testable import SwiftTUICore

@Suite
struct PreparedMeshGradientCacheTests {
  @Test("cached preparation samples match fresh preparation over the full bounds")
  func cachedPreparationMatchesFresh() {
    let cache = PreparedMeshGradientCache()
    let input = cacheTestInput()
    let bounds = cacheTestBounds()
    let cached = cache.prepared(for: input, bounds: bounds)
    let fresh = PreparedMeshGradient(input: input, bounds: bounds)

    for y in bounds.origin.y..<(bounds.origin.y + bounds.size.height) {
      for x in bounds.origin.x..<(bounds.origin.x + bounds.size.width) {
        #expect(cached.color(atCellX: x, y: y) == fresh.color(atCellX: x, y: y))
      }
    }
  }

  @Test("repeated input and bounds prepare exactly once")
  func repeatedKeyHits() {
    let cache = PreparedMeshGradientCache()
    let input = cacheTestInput()
    let bounds = cacheTestBounds()

    let first = cache.prepared(for: input, bounds: bounds)
    let second = cache.prepared(for: input, bounds: bounds)

    #expect(first.color(atCellX: 3, y: 2) == second.color(atCellX: 3, y: 2))
    #expect(
      cache.metrics
        == .init(entries: 1, lookups: 2, hits: 1, misses: 1, stores: 1)
    )
  }

  @Test("every preparation input and bounds axis participates in the key")
  func everyKeyAxisMisses() {
    let cache = PreparedMeshGradientCache(capacity: 16)
    let base = cacheTestInput()
    let bounds = cacheTestBounds()
    _ = cache.prepared(for: base, bounds: bounds)

    var changedPoints = base
    changedPoints.points[4] = .init(0.72, 0.18)
    _ = cache.prepared(for: changedPoints, bounds: bounds)

    var changedColors = base
    changedColors.colors[4] = Color(red: 1, green: 0.45, blue: 0)
    _ = cache.prepared(for: changedColors, bounds: bounds)

    var changedBackground = base
    changedBackground.background = .gray
    _ = cache.prepared(for: changedBackground, bounds: bounds)

    var changedSmoothing = base
    changedSmoothing.smoothsColors.toggle()
    _ = cache.prepared(for: changedSmoothing, bounds: bounds)

    var changedColorSpace = base
    changedColorSpace.colorSpace = .device
    _ = cache.prepared(for: changedColorSpace, bounds: bounds)

    let changedBounds = CellRect(
      origin: bounds.origin,
      size: .init(width: bounds.size.width + 1, height: bounds.size.height)
    )
    _ = cache.prepared(for: base, bounds: changedBounds)

    #expect(cache.metrics.entries == 7)
    #expect(cache.metrics.lookups == 7)
    #expect(cache.metrics.hits == 0)
    #expect(cache.metrics.misses == 7)
    #expect(cache.metrics.stores == 7)
  }

  @Test("animated MeshGradient mutation cannot alter a cached value")
  func meshGradientMutationKeepsCachedEntryIsolated() {
    let cache = PreparedMeshGradientCache()
    var gradient = cacheTestGradient()
    let oldInput = cacheInput(for: gradient)
    let bounds = cacheTestBounds()
    let oldPrepared = cache.prepared(for: oldInput, bounds: bounds)
    let oldSample = oldPrepared.color(atCellX: 3, y: 2)

    var targetPoints = gradient.points
    targetPoints[4] = .init(0.8, 0.15)
    var targetColors = gradient.colors
    targetColors[4] = Color(red: 1, green: 0.45, blue: 0)
    gradient.replaceAnimatedValues(
      points: targetPoints,
      colors: targetColors,
      background: .white
    )
    let newInput = cacheInput(for: gradient)
    let retainedOld = cache.prepared(for: oldInput, bounds: bounds)
    let newPrepared = cache.prepared(for: newInput, bounds: bounds)

    #expect(retainedOld.color(atCellX: 3, y: 2) == oldSample)
    #expect(newPrepared.color(atCellX: 3, y: 2) != oldSample)
    #expect(cache.metrics.entries == 2)
    #expect(cache.metrics.lookups == 3)
    #expect(cache.metrics.hits == 1)
    #expect(cache.metrics.misses == 2)
  }

  @Test("capacity eviction removes the least recently used admitted key")
  func capacityEvictsLeastRecentlyUsed() {
    let cache = PreparedMeshGradientCache(capacity: 2)
    let bounds = cacheTestBounds()
    let alpha = cacheTestInput()
    let beta = offsetInput(alpha, red: 0.1)
    let gamma = offsetInput(alpha, red: 0.2)

    _ = cache.prepared(for: alpha, bounds: bounds)
    _ = cache.prepared(for: beta, bounds: bounds)
    _ = cache.prepared(for: alpha, bounds: bounds)
    _ = cache.prepared(for: gamma, bounds: bounds)
    _ = cache.prepared(for: gamma, bounds: bounds)

    #expect(cache.metrics.entries == 2)
    #expect(cache.metrics.evictions == 1)
    #expect(cache.metrics.bypassedStores == 1)

    let beforeAlpha = cache.metrics
    _ = cache.prepared(for: alpha, bounds: bounds)
    #expect(cache.metrics.hits == beforeAlpha.hits + 1)

    let beforeBeta = cache.metrics
    _ = cache.prepared(for: beta, bounds: bounds)
    #expect(cache.metrics.misses == beforeBeta.misses + 1)
  }

  @Test("full cache bypasses a first sighting and admits a repeated key")
  func admissionGateRequiresRepeatSighting() {
    let cache = PreparedMeshGradientCache(capacity: 1)
    let bounds = cacheTestBounds()
    let hot = cacheTestInput()
    let candidate = offsetInput(hot, red: 0.2)

    _ = cache.prepared(for: hot, bounds: bounds)
    _ = cache.prepared(for: candidate, bounds: bounds)

    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.stores == 1)
    #expect(cache.metrics.evictions == 0)
    #expect(cache.metrics.bypassedStores == 1)

    _ = cache.prepared(for: candidate, bounds: bounds)
    #expect(cache.metrics.entries == 1)
    #expect(cache.metrics.stores == 2)
    #expect(cache.metrics.evictions == 1)
    #expect(cache.metrics.bypassedStores == 1)
  }

  @Test("warm hits keep the access log bounded")
  func warmHitsKeepAccessLogBounded() {
    let capacity = 4
    let cache = PreparedMeshGradientCache(capacity: capacity)
    let bounds = cacheTestBounds()
    let inputs = (0..<capacity).map { offsetInput(cacheTestInput(), red: Double($0) * 0.05) }

    for input in inputs {
      _ = cache.prepared(for: input, bounds: bounds)
    }
    for _ in 0..<2_000 {
      for input in inputs {
        _ = cache.prepared(for: input, bounds: bounds)
      }
    }

    #expect(cache.metrics.entries == capacity)
    #expect(cache.metrics.evictions == 0)
    #expect(cache.accessLogDepth <= capacity * 4)
  }

  @Test("reset clears entries logs admission history and metrics")
  func resetClearsState() {
    let cache = PreparedMeshGradientCache(capacity: 1)
    let bounds = cacheTestBounds()
    let first = cacheTestInput()
    let second = offsetInput(first, red: 0.2)

    _ = cache.prepared(for: first, bounds: bounds)
    _ = cache.prepared(for: second, bounds: bounds)
    cache.reset()

    #expect(cache.metrics == .init())
    #expect(cache.accessLogDepth == 0)

    _ = cache.prepared(for: second, bounds: bounds)
    #expect(
      cache.metrics
        == .init(entries: 1, lookups: 1, hits: 0, misses: 1, stores: 1)
    )
  }
}

private func cacheTestGradient() -> MeshGradient {
  MeshGradient(
    width: 3,
    height: 3,
    points: [
      .init(0, 0), .init(0.5, 0), .init(1, 0),
      .init(0, 0.5), .init(0.65, 0.2), .init(1, 0.5),
      .init(0, 1), .init(0.5, 1), .init(1, 1),
    ],
    colors: [
      .red, .green, .blue,
      .yellow, .magenta, .cyan,
      .white, .gray, .black,
    ],
    background: .black,
    smoothsColors: true,
    colorSpace: .perceptual
  )
}

private func cacheTestInput() -> MeshGradientRasterInput {
  cacheInput(for: cacheTestGradient())
}

private func cacheInput(for gradient: MeshGradient) -> MeshGradientRasterInput {
  MeshGradientRasterInput(
    width: gradient.width,
    height: gradient.height,
    points: gradient.points,
    colors: gradient.colors,
    background: gradient.background,
    smoothsColors: gradient.smoothsColors,
    colorSpace: gradient.colorSpace == .device ? .device : .perceptual
  )
}

private func offsetInput(
  _ input: MeshGradientRasterInput,
  red: Double
) -> MeshGradientRasterInput {
  var copy = input
  copy.colors[0] = Color(red: red, green: 0.1, blue: 0.2)
  return copy
}

private func cacheTestBounds() -> CellRect {
  CellRect(origin: .init(x: 1, y: 1), size: .init(width: 8, height: 5))
}
