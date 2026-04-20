import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI

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

  @Test("StreamingTerminalHost surface reflects updated cellPixelSize")
  func streamingHostUpdateCellPixelSize() {
    let host = StreamingTerminalHost(
      surfaceSize: Size(width: 80, height: 24),
      graphicsCapabilities: TerminalGraphicsCapabilities(
        cellPixelSize: Size(width: 8, height: 16)
      ),
      outputHandler: { _ in }
    )

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 8, height: 16))

    host.updateCellPixelSize(Size(width: 12, height: 24))

    #expect(host.graphicsCapabilities.cellPixelSize == Size(width: 12, height: 24))
  }

  @Test("StreamingTerminalHost clears cell pixel size on nil update")
  func streamingHostClearsCellPixelSize() {
    let host = StreamingTerminalHost(
      surfaceSize: Size(width: 80, height: 24),
      graphicsCapabilities: TerminalGraphicsCapabilities(
        cellPixelSize: Size(width: 10, height: 20)
      ),
      outputHandler: { _ in }
    )

    host.updateCellPixelSize(nil)

    #expect(host.graphicsCapabilities.cellPixelSize == nil)
  }

  @Test("HostedSceneSession.resize carries cellPixelSize into the host")
  @MainActor
  func hostedResizeUpdatesCellPixelSize() {
    let session = HostedSceneSession(
      descriptor: TerminalUISceneDescriptor(
        id: WindowIdentifier("test"),
        title: nil,
        isDefault: true
      ),
      rootIdentity: Identity(components: ["test"]),
      sessionName: "test",
      initialSize: Size(width: 80, height: 24),
      appearance: .fallback,
      theme: nil,
      capabilityProfile: .trueColor,
      runScene: { _, _, _ in
        RunLoopResult(
          finalState: TerminalUISceneSessionState(),
          renderedFrames: 0,
          exitReason: .inputEnded
        )
      },
      onOutput: { _ in }
    )

    session.resize(to: Size(width: 80, height: 24), cellPixelSize: Size(width: 12, height: 24))

    #expect(session.hostGraphicsCapabilitiesForTesting.cellPixelSize == Size(width: 12, height: 24))
  }

  @Test("SIGWINCH-driven refresh surfaces new metrics in the next GeometryReader proxy")
  @MainActor
  func sigwinchRefreshSurfacesInProxy() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = Size(width: 40, height: 10)
    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 8, height: 16, source: .reported
    )

    let first = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("w=\(proxy.cellPixelMetrics.width)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )
    #expect(first.rasterSurface.lines.contains("w=8"))

    environmentValues.cellPixelMetrics = CellPixelMetrics(
      width: 12, height: 24, source: .reported
    )

    let second = DefaultRenderer().render(
      GeometryReader { proxy in
        Text("w=\(proxy.cellPixelMetrics.width)")
      },
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues
      )
    )
    #expect(second.rasterSurface.lines.contains("w=12"))
  }
}
