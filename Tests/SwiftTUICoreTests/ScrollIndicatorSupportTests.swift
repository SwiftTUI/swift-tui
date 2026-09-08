import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Scroll indicator support")
struct ScrollIndicatorSupportTests {
  @Test("a converged layout viewport wins over a cold indicator fixed point")
  func convergedViewport() throws {
    let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 6))
    let viewport = CellRect(origin: .zero, size: .init(width: 7, height: 5))
    #expect(
      resolvedScrollIndicatorMetrics(
        viewportRect: bounds, contentBounds: bounds, axes: [.horizontal, .vertical],
        axis: .vertical) == nil)
    let vertical = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: bounds, contentBounds: bounds, axes: [.horizontal, .vertical],
        axis: .vertical, contentViewportRect: viewport))
    let horizontal = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: bounds, contentBounds: bounds, axes: [.horizontal, .vertical],
        axis: .horizontal, contentViewportRect: viewport))
    #expect(vertical.viewportLength == 5)
    #expect(horizontal.viewportLength == 7)
    #expect(vertical.maxOffset == 1)
    #expect(horizontal.maxOffset == 1)
  }

  @Test("overlay tracks share no corner cell and retain the full scroll range")
  func overlayCorner() throws {
    let viewport = CellRect(origin: .init(x: 3, y: 2), size: .init(width: 8, height: 6))
    let content = CellRect(origin: .zero, size: .init(width: 24, height: 18))
    let vertical = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: viewport, contentBounds: content, axes: [.horizontal, .vertical],
        axis: .vertical, reservesSpace: false))
    let horizontal = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: viewport, contentBounds: content, axes: [.horizontal, .vertical],
        axis: .horizontal, reservesSpace: false))
    #expect(horizontal.rect.size.width == 7)
    #expect(vertical.rect.size.height == 6)
    #expect(horizontal.rect.origin.x + horizontal.rect.size.width == vertical.rect.origin.x)
    #expect(horizontal.viewportLength == 8)
    #expect(horizontal.maxOffset == 16)
    #expect(vertical.maxOffset == 12)
    #expect(
      horizontal.targetOffset(
        for: .cellFallback(.init(x: 9, y: 7)), currentOffset: 0) == 16)
    #expect(
      vertical.targetOffset(
        for: .cellFallback(.init(x: 10, y: 7)), currentOffset: 0) == 12)
  }

  @Test("vertical target offsets use fractional pointer coordinates")
  func verticalTargetOffsetsUseFractionalPointerCoordinates() throws {
    let metrics = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: .init(origin: .init(x: 20, y: 10), size: .init(width: 8, height: 8)),
        contentBounds: .init(origin: .zero, size: .init(width: 7, height: 24)),
        axes: .vertical,
        axis: .vertical
      )
    )

    #expect(
      metrics.targetOffset(
        for: precisePointer(at: .init(x: 27.5, y: 14.5)),
        currentOffset: 0
      ) == 10
    )
  }

  @Test("cell fallback target offsets keep whole-cell scroll behavior")
  func cellFallbackTargetOffsetsKeepWholeCellScrollBehavior() throws {
    let metrics = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 8)),
        contentBounds: .init(origin: .zero, size: .init(width: 7, height: 24)),
        axes: .vertical,
        axis: .vertical
      )
    )

    #expect(
      metrics.targetOffset(
        for: .cellFallback(.init(x: 7, y: 4)),
        currentOffset: 0
      ) == 9
    )
  }

  @Test("target offsets clamp out-of-track pointer coordinates")
  func targetOffsetsClampOutOfTrackPointerCoordinates() throws {
    let metrics = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: .init(origin: .zero, size: .init(width: 8, height: 8)),
        contentBounds: .init(origin: .zero, size: .init(width: 7, height: 24)),
        axes: .vertical,
        axis: .vertical
      )
    )

    #expect(
      metrics.targetOffset(
        for: precisePointer(at: .init(x: 7.5, y: -10)),
        currentOffset: 8
      ) == 0
    )
    #expect(
      metrics.targetOffset(
        for: precisePointer(at: .init(x: 7.5, y: 40)),
        currentOffset: 8
      ) == 16
    )
  }

  @Test("horizontal target offsets use fractional pointer coordinates")
  func horizontalTargetOffsetsUseFractionalPointerCoordinates() throws {
    let metrics = try #require(
      resolvedScrollIndicatorMetrics(
        viewportRect: .init(origin: .init(x: 10, y: 4), size: .init(width: 8, height: 6)),
        contentBounds: .init(origin: .zero, size: .init(width: 24, height: 5)),
        axes: .horizontal,
        axis: .horizontal
      )
    )

    #expect(
      metrics.targetOffset(
        for: precisePointer(at: .init(x: 14.5, y: 9.5)),
        currentOffset: 0
      ) == 10
    )
  }
}

private func precisePointer(
  at location: Point
) -> PointerLocation {
  .subCell(
    location: location,
    source: .nativePixels,
    metrics: .init(width: 10, height: 20, source: .reported)
  )
}
