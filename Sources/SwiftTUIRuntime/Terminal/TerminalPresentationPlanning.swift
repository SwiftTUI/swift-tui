import SwiftTUICore

struct TerminalPresentationPlan: Sendable {
  struct GraphicsReplayPlan: Equatable, Sendable {
    enum Scope: String, Equatable, Sendable {
      case none
      case targeted
      case full
    }

    var scope: Scope
    var attachmentsToReplay: [RasterImageAttachment]

    static let none = Self(
      scope: .none,
      attachmentsToReplay: []
    )
  }

  struct SpanUpdate: Equatable, Sendable {
    var row: Int
    var column: Int
    var renderedSpan: String
    var cellsChanged: Int
  }

  struct RowBatch: Equatable, Sendable {
    var row: Int
    var anchorColumn: Int
    var renderedBatch: String
    var spanUpdates: [SpanUpdate]

    var cellsChanged: Int {
      spanUpdates.reduce(0) { $0 + $1.cellsChanged }
    }

    func canLowerToEraseToEndOfLine(
      surfaceWidth: Int
    ) -> Bool {
      guard
        spanUpdates.count == 1,
        let span = spanUpdates.first,
        renderedBatch == span.renderedSpan,
        span.column == anchorColumn,
        span.column + span.cellsChanged >= surfaceWidth,
        !span.renderedSpan.isEmpty
      else {
        return false
      }

      return span.renderedSpan.allSatisfy { $0 == " " }
    }
  }

  enum Strategy: String, Equatable, Sendable {
    case fullRepaint
    case incremental
  }

  var strategy: Strategy
  var rowBatches: [RowBatch]
  var graphicsReplay: GraphicsReplayPlan
  var surfaceSize: CellSize

  static func fullRepaint(
    surfaceSize: CellSize
  ) -> Self {
    Self(
      strategy: .fullRepaint,
      rowBatches: [],
      graphicsReplay: .none,
      surfaceSize: surfaceSize
    )
  }

  static func incremental(
    rowBatches: [RowBatch],
    graphicsReplay: GraphicsReplayPlan,
    surfaceSize: CellSize
  ) -> Self {
    Self(
      strategy: .incremental,
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: surfaceSize
    )
  }

  var spanUpdates: [SpanUpdate] {
    rowBatches.flatMap(\.spanUpdates)
  }

  var linesTouched: Int {
    switch strategy {
    case .fullRepaint:
      surfaceSize.height
    case .incremental:
      Set(rowBatches.map(\.row)).count
    }
  }

  var cellsChanged: Int {
    switch strategy {
    case .fullRepaint:
      max(0, surfaceSize.width) * max(0, surfaceSize.height)
    case .incremental:
      rowBatches.reduce(0) { $0 + $1.cellsChanged }
    }
  }
}

struct TerminalPresentationPlanner {
  let capabilityProfile: TerminalCapabilityProfile
  let graphicsCapabilities: TerminalGraphicsCapabilities

  init(
    capabilityProfile: TerminalCapabilityProfile,
    graphicsCapabilities: TerminalGraphicsCapabilities = .none
  ) {
    self.capabilityProfile = capabilityProfile
    self.graphicsCapabilities = graphicsCapabilities
  }

  func plan(
    previousSurface: RasterSurface?,
    currentSurface: RasterSurface,
    damage: PresentationDamage? = nil
  ) -> TerminalPresentationPlan {
    guard let previousSurface,
      previousSurface.size == currentSurface.size,
      previousSurface.attachments == currentSurface.attachments,
      previousSurface.metadata == currentSurface.metadata
    else {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let supportsIncrementalGraphicsReplay = graphicsCapabilities.preferredProtocol == .kitty
    if previousSurface.imageAttachments != currentSurface.imageAttachments,
      !supportsIncrementalGraphicsReplay
    {
      return .fullRepaint(
        surfaceSize: currentSurface.size
      )
    }

    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )

    let rowCount = max(
      max(previousSurface.cells.count, currentSurface.cells.count),
      currentSurface.size.height
    )
    let rowsToDiff: [Int] =
      if let damage {
        damage.dirtyRows
          .filter { $0 >= 0 && $0 < rowCount }
          .sorted()
      } else {
        Array(0..<rowCount)
      }
    var rowBatches: [TerminalPresentationPlan.RowBatch] = []

    for row in rowsToDiff {
      let previousRow = row < previousSurface.cells.count ? previousSurface.cells[row] : []
      let currentRow = row < currentSurface.cells.count ? currentSurface.cells[row] : []
      let rowSpans = renderer.diffSpans(
        previousRow: previousRow,
        currentRow: currentRow,
        width: max(
          previousSurface.size.width,
          currentSurface.size.width,
          previousRow.count,
          currentRow.count
        ),
        limitingTo: damage?.columnRanges(for: row)
      )

      if let rowBatch = renderer.renderRowBatch(
        row: row,
        currentRow: currentRow,
        spans: rowSpans
      ) {
        rowBatches.append(rowBatch)
      }
    }

    let graphicsReplay = graphicsReplayPlan(
      previousAttachments: previousSurface.imageAttachments,
      currentAttachments: currentSurface.imageAttachments,
      dirtyRows: Set(rowBatches.map(\.row)),
      supportsIncrementalGraphicsReplay: supportsIncrementalGraphicsReplay
    )

    return .incremental(
      rowBatches: rowBatches,
      graphicsReplay: graphicsReplay,
      surfaceSize: currentSurface.size
    )
  }

  private func graphicsReplayPlan(
    previousAttachments: [RasterImageAttachment],
    currentAttachments: [RasterImageAttachment],
    dirtyRows: Set<Int>,
    supportsIncrementalGraphicsReplay: Bool
  ) -> TerminalPresentationPlan.GraphicsReplayPlan {
    guard supportsIncrementalGraphicsReplay else {
      return .none
    }
    guard !previousAttachments.isEmpty || !currentAttachments.isEmpty else {
      return .none
    }

    if previousAttachments != currentAttachments {
      return .init(
        scope: .full,
        attachmentsToReplay: currentAttachments
      )
    }

    let attachmentsToReplay = currentAttachments.filter { attachment in
      attachment.visibleBoundsIntersectsAnyDirtyRow(dirtyRows)
    }
    guard !attachmentsToReplay.isEmpty else {
      return .none
    }

    return .init(
      scope: .targeted,
      attachmentsToReplay: attachmentsToReplay
    )
  }
}

extension RasterImageAttachment {
  fileprivate func visibleBoundsIntersectsAnyDirtyRow(_ dirtyRows: Set<Int>) -> Bool {
    guard !dirtyRows.isEmpty else {
      return false
    }

    let lowerRow = visibleBounds.origin.y
    let upperRow = visibleBounds.origin.y + visibleBounds.size.height
    guard lowerRow < upperRow else {
      return false
    }

    return dirtyRows.contains { dirtyRow in
      dirtyRow >= lowerRow && dirtyRow < upperRow
    }
  }
}
