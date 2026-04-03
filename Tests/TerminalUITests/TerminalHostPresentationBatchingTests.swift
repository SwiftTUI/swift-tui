import Dispatch
import Testing

@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct TerminalHostPresentationBatchingTests {
  @Test("terminal host batches a full repaint into one write")
  func fullRepaintBatchesWrites() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 2),
        lines: ["ABCD", "EFGH"]
      )
    )
    try host.drainPendingPresentation()

    #expect(controller.writes.count == 1)
    #expect(controller.writes.first == "\u{001B}[2J\u{001B}[1;1HABCD\u{001B}[2;1HEFGH")
  }

  @Test("terminal host batches incremental spans into one write")
  func incrementalUpdatesBatchedIntoOneWrite() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alpha"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alpXa"]
      )
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(incrementalWrites == ["\u{001B}[1;4HX"])
  }

  @Test("terminal host damage-aware presentation batches only hinted rows")
  func damageAwareUpdatesBatchOnlyHintedRows() throws {
    let controller = PresentationWriteCountingController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 2),
        lines: ["same", "beta"]
      )
    )
    try host.drainPendingPresentation()
    let writesBeforeUpdate = controller.writes.count

    let damageAwareHost: any DamageAwareTerminalHosting = host
    _ = try damageAwareHost.present(
      RasterSurface(
        size: .init(width: 8, height: 2),
        lines: ["same", "beXa"]
      ),
      damage: .init(dirtyRows: [1])
    )
    try host.drainPendingPresentation()

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))
    #expect(incrementalWrites == ["\u{001B}[2;3HX"])
  }

  @Test("terminal host drops stale pending frames and forces a full repaint on recovery")
  func droppedPendingFramesForceFullRepaintRecovery() throws {
    let controller = BlockingPresentationWriteController(isTTY: true)
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24),
      controller: controller,
      capabilityProfile: .previewUnicode
    )

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["AAAA"]
      )
    )
    #expect(controller.waitForBlockedWriteToStart())

    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["BAAA"]
      )
    )
    _ = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["ABAA"]
      )
    )

    controller.unblockWrite()
    try host.drainPendingPresentation()

    #expect(
      controller.writes == [
        "\u{001B}[2J\u{001B}[1;1HAAAA",
        "\u{001B}[1;1HAB",
      ]
    )

    let metrics = try host.present(
      RasterSurface(
        size: .init(width: 4, height: 1),
        lines: ["WXYZ"]
      )
    )
    try host.drainPendingPresentation()

    #expect(metrics.strategy == .fullRepaint)
    #expect(
      controller.writes.last == "\u{001B}[2J\u{001B}[1;1HWXYZ"
    )
  }
}

private final class PresentationWriteCountingController: TerminalControlling, @unchecked Sendable {
  private let isTTYValue: Bool
  private(set) var writes: [String] = []

  init(isTTY: Bool) {
    isTTYValue = isTTY
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> Size? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    writes.append(output)
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }
}

private final class BlockingPresentationWriteController: TerminalControlling, @unchecked Sendable {
  private let isTTYValue: Bool
  private let blockedWriteStarted = DispatchSemaphore(value: 0)
  private let releaseBlockedWrite = DispatchSemaphore(value: 0)

  private var shouldBlockFirstWrite = true
  private(set) var writes: [String] = []

  init(isTTY: Bool) {
    isTTYValue = isTTY
  }

  func isATTY(_: Int32) -> Bool {
    isTTYValue
  }

  func getAttributes(from _: Int32) throws -> termios {
    termios()
  }

  func setAttributes(_: termios, on _: Int32) throws {}

  func windowSize(of _: Int32) throws -> Size {
    .init(width: 80, height: 24)
  }

  func cellPixelSize(of _: Int32) throws -> Size? {
    nil
  }

  func getFileStatusFlags(of _: Int32) throws -> Int32 {
    0
  }

  func setFileStatusFlags(_: Int32, on _: Int32) throws {}

  func write(_ output: String, to _: Int32) throws {
    if shouldBlockFirstWrite {
      shouldBlockFirstWrite = false
      blockedWriteStarted.signal()
      guard releaseBlockedWrite.wait(timeout: .now() + 1) == .success else {
        throw TerminalHostError.failedToWrite(errno: ETIMEDOUT)
      }
    }

    writes.append(output)
  }

  func read(
    from _: Int32,
    maxBytes _: Int,
    timeoutMilliseconds _: Int
  ) throws -> [UInt8] {
    []
  }

  func waitForBlockedWriteToStart() -> Bool {
    blockedWriteStarted.wait(timeout: .now() + 1) == .success
  }

  func unblockWrite() {
    releaseBlockedWrite.signal()
  }
}
