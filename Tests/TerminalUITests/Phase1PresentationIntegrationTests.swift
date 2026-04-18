import Testing

@testable import Core
@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct Phase1PresentationIntegrationTests {
  @Test("button press presents as a thin incremental span")
  func buttonPressPresentsAsThinIncrementalSpan() throws {
    let result = try presentScenario(
      previous: .init(
        size: .init(width: 16, height: 2),
        lines: [
          "Save: [ ]",
          "Ready",
        ]
      ),
      current: .init(
        size: .init(width: 16, height: 2),
        lines: [
          "Save: [x]",
          "Ready",
        ]
      )
    )

    #expect(result.metrics.strategy == .incremental)
    #expect(result.metrics.cellsChanged == 1)
    #expect(result.metrics.bytesWritten < result.fullRepaintMetrics.bytesWritten)
    #expect(
      result.incrementalWrites.contains { write in
        write.contains("\u{001B}[1;8H")
      }
    )
  }

  @Test("text input updates through a single cursor-addressed span")
  func textInputUpdatesThroughSingleCursorAddressedSpan() throws {
    let result = try presentScenario(
      previous: .init(
        size: .init(width: 16, height: 2),
        lines: [
          "Name: Ada_",
          "Ready",
        ]
      ),
      current: .init(
        size: .init(width: 16, height: 2),
        lines: [
          "Name: AdaL_",
          "Ready",
        ]
      )
    )

    #expect(result.metrics.strategy == .incremental)
    #expect(result.metrics.cellsChanged == 2)
    #expect(result.metrics.bytesWritten < result.fullRepaintMetrics.bytesWritten)
    #expect(
      result.incrementalWrites.contains { write in
        write.contains("\u{001B}[1;10H")
      }
    )
  }

  @Test("focus movement only rewrites the touched focus markers")
  func focusMovementOnlyRewritesTouchedFocusMarkers() throws {
    let result = try presentScenario(
      previous: .init(
        size: .init(width: 14, height: 2),
        lines: [
          "> First",
          "  Second",
        ]
      ),
      current: .init(
        size: .init(width: 14, height: 2),
        lines: [
          "  First",
          "> Second",
        ]
      )
    )

    #expect(result.metrics.strategy == .incremental)
    #expect(result.metrics.linesTouched == 2)
    #expect(result.metrics.cellsChanged == 2)
    #expect(result.metrics.bytesWritten < result.fullRepaintMetrics.bytesWritten)
    #expect(
      result.incrementalWrites.contains { write in
        write.contains("\u{001B}[1;1H")
      }
    )
    #expect(
      result.incrementalWrites.contains { write in
        write.contains("\u{001B}[2;1H")
      }
    )
  }

  @Test("scroll steps stay incremental and smaller than a full repaint")
  func scrollStepsStayIncremental() throws {
    let result = try presentScenario(
      previous: .init(
        size: .init(width: 16, height: 3),
        lines: [
          "Item 1",
          "Item 2",
          "Item 3",
        ]
      ),
      current: .init(
        size: .init(width: 16, height: 3),
        lines: [
          "Item 2",
          "Item 3",
          "Item 4",
        ]
      )
    )

    #expect(result.metrics.strategy == .incremental)
    #expect(result.metrics.cellsChanged == 3)
    #expect(result.metrics.bytesWritten < result.fullRepaintMetrics.bytesWritten)
  }

  @Test("resize still triggers a safe full repaint fallback")
  func resizeTriggersSafeFullRepaintFallback() throws {
    let controller = PresentationController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    let initial = RasterSurface(
      size: .init(width: 8, height: 2),
      lines: ["alpha", "bravo"]
    )
    _ = try host.present(initial)
    try host.drainPendingPresentation()

    let resized = RasterSurface(
      size: .init(width: 10, height: 2),
      lines: ["alpha", "bravo"]
    )
    let metrics = try host.present(resized)
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .fullRepaint)
    #expect(metrics.usedFullRepaint)
    #expect(
      controller.writes.last
        == "\u{001B}[2J\u{001B}[1;1Halpha\u{001B}[2;1Hbravo"
    )
  }
}

private struct PresentationScenarioResult {
  let metrics: TerminalPresentationMetrics
  let fullRepaintMetrics: TerminalPresentationMetrics
  let incrementalWrites: [String]
}

private func presentScenario(
  previous: RasterSurface,
  current: RasterSurface
) throws -> PresentationScenarioResult {
  let controller = PresentationController()
  let host = TerminalHost(
    inputFileDescriptor: 0,
    outputFileDescriptor: 1,
    fallbackSize: .init(width: 80, height: 24),
    controller: controller,
    capabilityProfile: .previewUnicode
  )
  _ = try host.present(previous)
  try host.drainPendingPresentation()
  let writesBeforeUpdate = controller.writes.count
  let metrics = try host.present(current)
  try host.drainPendingPresentation()
  let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))
  let fullRepaintMetrics = TerminalPresentationMetrics.fullRepaint(
    for: current,
    capabilityProfile: .previewUnicode
  )

  return PresentationScenarioResult(
    metrics: metrics,
    fullRepaintMetrics: fullRepaintMetrics,
    incrementalWrites: incrementalWrites
  )
}

private final class PresentationController: TerminalControlling {
  private let writesStorage = LockedBox<[String]>([])

  private(set) var writes: [String] {
    get { writesStorage.value }
    set { writesStorage.value = newValue }
  }

  func isATTY(_: Int32) -> Bool {
    true
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}
