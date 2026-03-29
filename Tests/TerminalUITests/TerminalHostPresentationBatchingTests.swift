import Testing

@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

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
    let writesBeforeUpdate = controller.writes.count

    _ = try host.present(
      RasterSurface(
        size: .init(width: 8, height: 1),
        lines: ["alpXa"]
      )
    )

    let incrementalWrites = Array(controller.writes.dropFirst(writesBeforeUpdate))

    #expect(incrementalWrites == ["\u{001B}[1;4HX"])
  }
}

private final class PresentationWriteCountingController: TerminalControlling {
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
