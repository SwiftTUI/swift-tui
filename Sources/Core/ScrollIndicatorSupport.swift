package enum ScrollIndicatorAxis: Equatable, Sendable {
  case horizontal
  case vertical
}

package struct ScrollIndicatorInsets: Equatable, Sendable {
  package var trailing: Int
  package var bottom: Int

  package init(trailing: Int = 0, bottom: Int = 0) {
    self.trailing = trailing
    self.bottom = bottom
  }
}

package struct ScrollIndicatorMetrics: Equatable, Sendable {
  package var axis: ScrollIndicatorAxis
  package var rect: Rect
  package var maxOffset: Int
  package var viewportLength: Int
  package var contentLength: Int

  package init(
    axis: ScrollIndicatorAxis,
    rect: Rect,
    maxOffset: Int,
    viewportLength: Int,
    contentLength: Int
  ) {
    self.axis = axis
    self.rect = rect
    self.maxOffset = max(0, maxOffset)
    self.viewportLength = max(0, viewportLength)
    self.contentLength = max(0, contentLength)
  }

  package func thumbRange(
    for offset: Int
  ) -> Range<Int>? {
    guard maxOffset > 0 else {
      return nil
    }

    let trackRange = thumbTrackRange
    let trackLength = trackRange.upperBound - trackRange.lowerBound
    guard trackLength > 0 else {
      return nil
    }

    let thumbLength = proportionalThumbLength(for: trackLength)
    let availableTravel = trackLength - thumbLength
    guard availableTravel > 0 else {
      return trackRange.lowerBound..<(trackRange.lowerBound + thumbLength)
    }

    let clampedOffset = min(max(0, offset), maxOffset)
    let thumbStart =
      trackRange.lowerBound
      + Int(
        (Double(clampedOffset) / Double(maxOffset) * Double(availableTravel)).rounded()
      )
    return thumbStart..<(thumbStart + thumbLength)
  }

  package func targetOffset(
    for location: Point,
    currentOffset: Int
  ) -> Int {
    guard maxOffset > 0 else {
      return 0
    }

    let trackRange = thumbTrackRange
    let trackLength = trackRange.upperBound - trackRange.lowerBound
    guard trackLength > 1 else {
      return min(max(0, currentOffset), maxOffset)
    }

    let coordinate = axisCoordinate(for: location)
    let clampedCoordinate = min(max(coordinate, trackRange.lowerBound), trackRange.upperBound - 1)
    let progress = Double(clampedCoordinate - trackRange.lowerBound) / Double(trackLength - 1)
    return Int((progress * Double(maxOffset)).rounded())
  }

  private var axisOrigin: Int {
    switch axis {
    case .horizontal:
      rect.origin.x
    case .vertical:
      rect.origin.y
    }
  }

  private var axisLength: Int {
    switch axis {
    case .horizontal:
      rect.size.width
    case .vertical:
      rect.size.height
    }
  }

  private func axisCoordinate(
    for location: Point
  ) -> Int {
    switch axis {
    case .horizontal:
      location.x
    case .vertical:
      location.y
    }
  }

  private var thumbTrackRange: Range<Int> {
    let start = axisOrigin + (axisLength > 2 ? 1 : 0)
    let end = axisOrigin + axisLength - (axisLength > 2 ? 1 : 0)
    return start..<max(start, end)
  }

  private func proportionalThumbLength(
    for trackLength: Int
  ) -> Int {
    guard trackLength > 0 else { return 0 }
    guard contentLength > 0, viewportLength > 0 else { return 1 }

    let ratio = Double(viewportLength) / Double(contentLength)
    let minimumThumbLength = trackLength > 3 ? 2 : 1
    return min(
      trackLength,
      max(minimumThumbLength, Int((ratio * Double(trackLength)).rounded(.up)))
    )
  }
}

package func resolvedScrollIndicatorInsets(
  viewportRect: Rect,
  contentBounds: Rect,
  axes: AxisSet
) -> ScrollIndicatorInsets {
  var trailing = 0
  var bottom = 0

  for _ in 0..<3 {
    let viewportWidth = max(0, viewportRect.size.width - trailing)
    let viewportHeight = max(0, viewportRect.size.height - bottom)
    let nextTrailing =
      axes.contains(.vertical) && contentBounds.size.height > viewportHeight ? 1 : 0
    let nextBottom =
      axes.contains(.horizontal) && contentBounds.size.width > viewportWidth ? 1 : 0
    if nextTrailing == trailing, nextBottom == bottom {
      return .init(trailing: trailing, bottom: bottom)
    }
    trailing = nextTrailing
    bottom = nextBottom
  }

  return .init(trailing: trailing, bottom: bottom)
}

package func resolvedScrollIndicatorMetrics(
  viewportRect: Rect,
  contentBounds: Rect,
  axes: AxisSet,
  axis: ScrollIndicatorAxis
) -> ScrollIndicatorMetrics? {
  let insets = resolvedScrollIndicatorInsets(
    viewportRect: viewportRect,
    contentBounds: contentBounds,
    axes: axes
  )

  switch axis {
  case .vertical:
    guard axes.contains(.vertical), viewportRect.size.width > 0, viewportRect.size.height > 0 else {
      return nil
    }

    let viewportHeight = max(0, viewportRect.size.height - insets.bottom)
    let maxOffset = max(0, contentBounds.size.height - viewportHeight)
    guard maxOffset > 0 else {
      return nil
    }

    return .init(
      axis: .vertical,
      rect: .init(
        origin: .init(
          x: viewportRect.origin.x + viewportRect.size.width - 1, y: viewportRect.origin.y),
        size: .init(width: 1, height: viewportRect.size.height)
      ),
      maxOffset: maxOffset,
      viewportLength: viewportHeight,
      contentLength: contentBounds.size.height
    )
  case .horizontal:
    let trackWidth = max(0, viewportRect.size.width - insets.trailing)
    guard axes.contains(.horizontal), trackWidth > 0, viewportRect.size.height > 0 else {
      return nil
    }

    let maxOffset = max(0, contentBounds.size.width - trackWidth)
    guard maxOffset > 0 else {
      return nil
    }

    return .init(
      axis: .horizontal,
      rect: .init(
        origin: .init(
          x: viewportRect.origin.x, y: viewportRect.origin.y + viewportRect.size.height - 1),
        size: .init(width: trackWidth, height: 1)
      ),
      maxOffset: maxOffset,
      viewportLength: trackWidth,
      contentLength: contentBounds.size.width
    )
  }
}
