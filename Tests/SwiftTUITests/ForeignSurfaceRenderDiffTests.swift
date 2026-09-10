import Foundation
import SwiftTUIViews
import Testing

@testable import SwiftTUIRuntime

/// The byte budget belongs to the framework's ForeignSurface presentation path.
/// Generate each frame explicitly so PTY scheduling cannot decide test coverage.
@MainActor
@Suite("Foreign surface render diff", .serialized)
struct ForeignSurfaceRenderDiffTests {
  @Test("scrolling foreign grids stay within the presentation byte budget")
  func scrollingGridByteBudget() throws {
    let host = try presentFrames(count: 64, delay: 0)
    #expect(host.presentationMetrics.count == 64)
    #expect(host.presentationMetrics.contains { $0.strategy == .incremental })
    #expect(host.bytesEmittedToTerminal < 200_000)
  }

  @Test("50ms presentation latency preserves incremental foreign surface commits")
  func latencyInjectedPresentationPreservesIncrementalCommitShape() throws {
    let host = try presentFrames(count: 24, delay: 0.050)
    let incremental = host.presentationMetrics.filter { $0.strategy == .incremental }
    #expect(host.presentationMetrics.count == 24)
    #expect(!incremental.isEmpty)
    #expect(incremental.allSatisfy { $0.linesTouched <= 24 })
    #expect(host.bytesEmittedToTerminal < 80_000)
  }

  private func presentFrames(count: Int, delay: TimeInterval) throws -> ByteCountingTerminalHost {
    let size = CellSize(width: 80, height: 24)
    let host = ByteCountingTerminalHost(surfaceSize: size, artificialPresentationDelay: delay)
    let renderer = DefaultRenderer()
    for generation in 0..<count {
      let cells = (0..<size.height).map { row in
        let text = "line \(generation + row) "
        return Array((text + String(repeating: "x", count: size.width)).prefix(size.width))
          .map { RasterCell(character: $0) }
      }
      let payload = ScrollingPayload(grid: ForeignGrid(size: size, cells: cells))
      let frame = renderer.render(
        ForeignSurface(payload: payload),
        proposal: ProposedSize(width: size.width, height: size.height)
      )
      _ = try host.present(frame.rasterSurface)
    }
    return host
  }
}

private struct ScrollingPayload: ForeignSurfacePayload {
  let grid: ForeignGrid
}

private final class ByteCountingTerminalHost: PresentationSurface {
  var surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance = .fallback
  private(set) var presentationMetrics: [TerminalPresentationMetrics] = []
  private(set) var outOfBandBytes = 0
  private var previousSurface: RasterSurface?
  private let artificialPresentationDelay: TimeInterval

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    artificialPresentationDelay: TimeInterval = 0
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.artificialPresentationDelay = artificialPresentationDelay
  }

  var bytesEmittedToTerminal: Int {
    outOfBandBytes + presentationMetrics.map(\.bytesWritten).reduce(0, +)
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    if artificialPresentationDelay > 0 {
      Thread.sleep(forTimeInterval: artificialPresentationDelay)
    }

    let plan = TerminalPresentationPlanner(
      capabilityProfile: capabilityProfile
    ).plan(
      previousSurface: previousSurface,
      currentSurface: surface
    )
    let metrics = metrics(for: plan, surface: surface)
    presentationMetrics.append(metrics)
    previousSurface = surface
    return metrics
  }

  func write(_ output: String) throws {
    outOfBandBytes += output.utf8.count
  }

  private func metrics(
    for plan: TerminalPresentationPlan,
    surface: RasterSurface
  ) -> TerminalPresentationMetrics {
    let bytesWritten =
      switch plan.strategy {
      case .fullRepaint:
        TerminalPresentationMetrics.fullRepaint(
          for: surface,
          capabilityProfile: capabilityProfile
        ).bytesWritten
      case .incremental:
        plan.rowBatches.reduce(0) { partial, rowBatch in
          partial
            + cursorSequence(row: rowBatch.row, column: rowBatch.anchorColumn).utf8.count
            + rowBatch.renderedBatch.utf8.count
        }
      }

    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: plan.linesTouched,
      cellsChanged: plan.cellsChanged,
      strategy: plan.strategy == .fullRepaint ? .fullRepaint : .incremental
    )
  }

  private func cursorSequence(row: Int, column: Int) -> String {
    "\u{001B}[\(max(1, row + 1));\(max(1, column + 1))H"
  }
}
