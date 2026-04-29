import Testing

@testable import Core

@Suite("Scroll indicator support")
struct ScrollIndicatorSupportTests {
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
      ) == 11
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
      ) == 10
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
      ) == 11
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
