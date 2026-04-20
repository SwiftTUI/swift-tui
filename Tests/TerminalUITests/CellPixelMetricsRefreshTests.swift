import Testing

@testable import Core
@testable import TerminalUI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite
struct CellPixelMetricsRefreshTests {
  /// Mock controller whose reported cellPixelSize can be changed between reads
  /// to simulate a SIGWINCH refresh.
  private final class MutableController: TerminalControlling {
    private let pixelSizeStorage: LockedBox<Size?>

    init(pixelSize: Size? = Size(width: 8, height: 16)) {
      pixelSizeStorage = LockedBox(pixelSize)
    }

    var pixelSize: Size? {
      get { pixelSizeStorage.value }
      set { pixelSizeStorage.value = newValue }
    }

    func isATTY(_: Int32) -> Bool { true }
    func getAttributes(from _: Int32) throws -> termios { termios() }
    func setAttributes(_: termios, on _: Int32) throws {}
    func windowSize(of _: Int32) throws -> Size { Size(width: 80, height: 24) }
    func cellPixelSize(of _: Int32) throws -> Size? { pixelSize }
    func getFileStatusFlags(of _: Int32) throws -> Int32 { 0 }
    func setFileStatusFlags(_: Int32, on _: Int32) throws {}
    func write(_: String, to _: Int32) throws {}
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }

  @Test("baselineGraphicsCapabilities reflects the latest ioctl read on each access")
  func baselineRefreshes() {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: Size(width: 80, height: 24),
      controller: controller
    )

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))

    controller.pixelSize = Size(width: 10, height: 20)

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 10, height: 20))
  }

  @Test("baselineGraphicsCapabilities preserves cached value on transient ioctl failure")
  func baselinePreservesCachedOnFailure() {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: Size(width: 80, height: 24),
      controller: controller
    )
    _ = host.graphicsCapabilities  // prime cache with (8, 16)

    controller.pixelSize = nil

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))
  }
}
