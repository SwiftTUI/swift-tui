@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@_spi(Runners) @testable import TermUIPerf

struct PerfTerminalHostTests {
  @Test("frame arriving during the final idle sleep is still observed")
  @MainActor
  func frameArrivingDuringFinalIdleSleepIsObserved() async throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 8, rows: 1))
    let clock = ContinuousClock()
    let startedAt = clock.now
    var currentTime = startedAt
    var sleepCount = 0

    let frame = try await PerfScenarioRunner.waitForFrameMatching(
      in: host,
      afterFrame: 0,
      timeout: .milliseconds(1),
      hardCap: .seconds(1),
      timeoutMarker: "ready",
      now: { currentTime },
      sleep: {
        sleepCount += 1
        _ = try host.present(
          RasterSurface(
            size: CellSize(width: 8, height: 1),
            lines: ["ready"]
          ))
        currentTime = startedAt.advanced(by: .milliseconds(2))
      },
      matches: { $0.text.contains("ready") }
    )

    #expect(sleepCount == 1)
    #expect(frame.frameNumber == 1)
    #expect(frame.text.contains("ready"))
  }

  @Test("raster presentation records full repaint metrics")
  func rasterPresentationRecordsFullRepaintMetrics() throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 6, rows: 2))
    let surface = RasterSurface(
      size: CellSize(width: 6, height: 2),
      lines: ["ABCDEF", "stable"]
    )

    let metrics = try host.present(surface)

    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.linesTouched == 2)
    #expect(metrics.cellsChanged == 12)
    #expect(host.presentedFrames.last?.metrics == metrics)
  }

  @Test("semantic host presentation records incremental damage metrics")
  func semanticHostPresentationRecordsIncrementalDamageMetrics() throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 6, rows: 2))
    let surface = RasterSurface(
      size: CellSize(width: 6, height: 2),
      lines: ["ABCDEF", "stable"]
    )
    let damage = PresentationDamage(
      textRows: [
        PresentationDamage.TextRow(row: 0, columnRanges: [2..<4]),
        PresentationDamage.TextRow(row: 1),
      ]
    )

    let metrics = try host.present(
      SemanticHostFrame(
        sequence: 1,
        raster: surface,
        semantics: SemanticSnapshot(),
        focusedIdentity: nil,
        rasterDamage: damage
      ))

    #expect(host.semanticHostFrameCapabilities == [.rasterDamage])
    #expect(metrics.strategy == .incremental)
    #expect(metrics.linesTouched == 2)
    #expect(metrics.cellsChanged == 8)
    #expect(host.presentedFrames.last?.metrics == metrics)
  }

  @Test("emission simulation host counts real planner bytes into the recorder")
  func emissionSimulationHostCountsRealPlannerBytes() throws {
    let recorder = PerfTerminalHost(size: PerfTerminalSize(columns: 8, rows: 3))
    let host = TerminalEmissionSimulationHost(
      surfaceSize: CellSize(width: 8, height: 3),
      onPresent: { surface, metrics in
        recorder.recordFrame(surface: surface, metrics: metrics)
      }
    )

    let firstMetrics = try host.present(
      RasterSurface(
        size: CellSize(width: 8, height: 3),
        lines: ["alpha", "bravo", "charlie"]
      ),
      damage: nil
    )
    #expect(firstMetrics.strategy == .fullRepaint)
    #expect(firstMetrics.bytesWritten > 0)
    // The lane's fixed profile has synchronized output ON.
    #expect(firstMetrics.usedSynchronizedOutput)
    #expect(recorder.presentedFrames.count == 1)
    #expect(recorder.presentedFrames.last?.metrics == firstMetrics)

    // A hinted single-row change plans incrementally against the previous
    // surface and emits only that row's escape bytes — real, small, nonzero.
    let secondMetrics = try host.present(
      RasterSurface(
        size: CellSize(width: 8, height: 3),
        lines: ["alpXa", "bravo", "charlie"]
      ),
      damage: PresentationDamage(dirtyRows: [0])
    )
    #expect(secondMetrics.strategy == .incremental)
    #expect(secondMetrics.linesTouched == 1)
    #expect(secondMetrics.bytesWritten > 0)
    #expect(secondMetrics.bytesWritten < firstMetrics.bytesWritten)
    // Single row batch: below the R2.1 threshold, so no sync wrap.
    #expect(!secondMetrics.usedSynchronizedOutput)

    // A multi-row change carries the R2.1 synchronized-output wrap, so
    // present_sync is observable in-lane.
    let thirdMetrics = try host.present(
      RasterSurface(
        size: CellSize(width: 8, height: 3),
        lines: ["alpYa", "brZvo", "charlie"]
      ),
      damage: PresentationDamage(dirtyRows: [0, 1])
    )
    #expect(thirdMetrics.strategy == .incremental)
    #expect(thirdMetrics.linesTouched == 2)
    #expect(thirdMetrics.usedSynchronizedOutput)
    #expect(recorder.presentedFrames.count == 3)

    // A cell-identical present emits nothing.
    let idleMetrics = try host.present(
      RasterSurface(
        size: CellSize(width: 8, height: 3),
        lines: ["alpYa", "brZvo", "charlie"]
      ),
      damage: PresentationDamage(dirtyRows: [])
    )
    #expect(idleMetrics.bytesWritten == 0)
    #expect(!idleMetrics.usedSynchronizedOutput)
  }
}
