import SwiftTUICore

/// A continuous size in the native host's layout coordinate space.
///
/// Hosts map this to their own layout units: SwiftUI/AppKit/UIKit use points,
/// while Android Compose can use pixels after applying density.
public struct HostLengthSize: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public struct HostedSurfaceConfirmedSlack: Equatable, Sendable {
  private struct AxisSlack: Equatable, Sendable {
    var preferred: Int
    var capacity: Int
  }

  private var width: AxisSlack?
  private var height: AxisSlack?

  public init() {}

  public mutating func update(
    preferredGridSize: CellSize?,
    renderedGridSize: CellSize?
  ) {
    width = updatedAxisSlack(
      preferred: preferredGridSize?.width,
      rendered: renderedGridSize?.width,
      current: width
    )
    height = updatedAxisSlack(
      preferred: preferredGridSize?.height,
      rendered: renderedGridSize?.height,
      current: height
    )
  }

  public func confirmedPreferredWidth(
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    confirmedPreferred(
      axisSlack: width,
      proposed: proposed,
      preferred: preferred,
      rendered: rendered
    )
  }

  public func confirmedPreferredHeight(
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    confirmedPreferred(
      axisSlack: height,
      proposed: proposed,
      preferred: preferred,
      rendered: rendered
    )
  }

  private func updatedAxisSlack(
    preferred: Int?,
    rendered: Int?,
    current: AxisSlack?
  ) -> AxisSlack? {
    guard let preferred, let rendered else {
      return nil
    }

    let normalizedPreferred = max(1, preferred)
    let normalizedRendered = max(1, rendered)
    if normalizedPreferred < normalizedRendered {
      return AxisSlack(preferred: normalizedPreferred, capacity: normalizedRendered)
    }
    if let current, normalizedPreferred == current.preferred,
      normalizedRendered <= current.capacity
    {
      return current
    }
    return nil
  }

  private func confirmedPreferred(
    axisSlack: AxisSlack?,
    proposed: Int,
    preferred: Int?,
    rendered: Int?
  ) -> Int? {
    guard let axisSlack, let preferred, let rendered else {
      return nil
    }

    guard max(1, preferred) == axisSlack.preferred,
      max(1, rendered) <= axisSlack.capacity,
      max(1, proposed) <= axisSlack.capacity
    else {
      return nil
    }

    return axisSlack.preferred
  }
}

public struct HostedSurfaceSizeNegotiation: Equatable, Sendable {
  public var size: HostLengthSize
  public var probeGridSize: CellSize?

  public init(
    size: HostLengthSize,
    probeGridSize: CellSize?
  ) {
    self.size = size
    self.probeGridSize = probeGridSize
  }
}

public struct HostedSurfaceSizeNegotiator: Sendable {
  public var cellSize: HostLengthSize
  public var preferredGridSize: CellSize?
  public var renderedGridSize: CellSize?
  public var fallbackGridSize: CellSize
  public var confirmedSlack: HostedSurfaceConfirmedSlack

  public init(
    cellSize: HostLengthSize,
    preferredGridSize: CellSize? = nil,
    renderedGridSize: CellSize? = nil,
    fallbackGridSize: CellSize = CellSize(width: 80, height: 24),
    confirmedSlack: HostedSurfaceConfirmedSlack = HostedSurfaceConfirmedSlack()
  ) {
    self.cellSize = cellSize
    self.preferredGridSize = preferredGridSize
    self.renderedGridSize = renderedGridSize
    self.fallbackGridSize = fallbackGridSize
    self.confirmedSlack = confirmedSlack
  }

  public func sizeThatFits(
    proposedWidth: Double?,
    proposedHeight: Double?
  ) -> HostLengthSize {
    negotiate(
      proposedWidth: proposedWidth,
      proposedHeight: proposedHeight
    ).size
  }

  public func negotiate(
    proposedWidth: Double?,
    proposedHeight: Double?
  ) -> HostedSurfaceSizeNegotiation {
    let width = resolvedAxis(
      preferred: preferredGridSize?.width,
      rendered: renderedGridSize?.width,
      fallback: fallbackGridSize.width,
      proposedLength: proposedWidth,
      cellLength: cellSize.width
    ) { proposed, preferred, rendered in
      confirmedSlack.confirmedPreferredWidth(
        proposed: proposed,
        preferred: preferred,
        rendered: rendered
      )
    }
    let height = resolvedAxis(
      preferred: preferredGridSize?.height,
      rendered: renderedGridSize?.height,
      fallback: fallbackGridSize.height,
      proposedLength: proposedHeight,
      cellLength: cellSize.height
    ) { proposed, preferred, rendered in
      confirmedSlack.confirmedPreferredHeight(
        proposed: proposed,
        preferred: preferred,
        rendered: rendered
      )
    }

    let probeGridSize: CellSize? =
      if width.probeCells != nil || height.probeCells != nil {
        CellSize(
          width: width.probeCells ?? width.cells,
          height: height.probeCells ?? height.cells
        )
      } else {
        nil
      }

    return HostedSurfaceSizeNegotiation(
      size: HostLengthSize(
        width: Double(width.cells) * cellSize.width,
        height: Double(height.cells) * cellSize.height
      ),
      probeGridSize: probeGridSize
    )
  }

  public func intrinsicContentSize(
    noIntrinsicMetric: Double
  ) -> HostLengthSize {
    guard let preferredGridSize else {
      return HostLengthSize(width: noIntrinsicMetric, height: noIntrinsicMetric)
    }

    return HostLengthSize(
      width: Double(max(1, preferredGridSize.width)) * cellSize.width,
      height: Double(max(1, preferredGridSize.height)) * cellSize.height
    )
  }

  private struct AxisNegotiation {
    var cells: Int
    var probeCells: Int?
  }

  private func resolvedAxis(
    preferred: Int?,
    rendered: Int?,
    fallback: Int,
    proposedLength: Double?,
    cellLength: Double,
    confirmedPreferred: (Int, Int?, Int?) -> Int?
  ) -> AxisNegotiation {
    let preferred = preferred.map { max(1, $0) }
    let rendered = rendered.map { max(1, $0) }

    if let proposedCells = proposedCells(
      for: proposedLength,
      cellLength: cellLength
    ) {
      if let confirmedPreferred = confirmedPreferred(proposedCells, preferred, rendered) {
        return AxisNegotiation(
          cells: max(1, min(confirmedPreferred, proposedCells)),
          probeCells: nil
        )
      }

      guard let preferred else {
        guard let rendered else {
          return AxisNegotiation(cells: 1, probeCells: proposedCells)
        }
        return AxisNegotiation(
          cells: max(1, min(rendered, proposedCells)),
          probeCells: nil
        )
      }
      if let rendered, proposedCells > rendered, preferred == rendered {
        return AxisNegotiation(cells: preferred, probeCells: proposedCells)
      }
      return AxisNegotiation(cells: max(1, min(preferred, proposedCells)), probeCells: nil)
    }

    return AxisNegotiation(cells: max(1, preferred ?? rendered ?? fallback), probeCells: nil)
  }

  private func proposedCells(
    for proposedLength: Double?,
    cellLength: Double
  ) -> Int? {
    guard let proposedLength,
      proposedLength.isFinite,
      proposedLength > 0,
      cellLength.isFinite,
      cellLength > 0
    else {
      return nil
    }

    return max(1, Int((proposedLength / cellLength).rounded(.down)))
  }
}
