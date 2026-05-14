import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

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
    private let pixelSizeStorage: LockedBox<PixelSize?>

    init(pixelSize: PixelSize? = PixelSize(width: 8, height: 16)) {
      pixelSizeStorage = LockedBox(pixelSize)
    }

    var pixelSize: PixelSize? {
      get { pixelSizeStorage.value }
      set { pixelSizeStorage.value = newValue }
    }

    func isATTY(_: Int32) -> Bool { true }
    func getAttributes(from _: Int32) throws -> termios { termios() }
    func setAttributes(_: termios, on _: Int32) throws {}
    func windowSize(of _: Int32) throws -> CellSize { CellSize(width: 80, height: 24) }
    func cellPixelSize(of _: Int32) throws -> PixelSize? { pixelSize }
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
      fallbackSize: CellSize(width: 80, height: 24),
      controller: controller
    )

    #expect(host.graphicsCapabilities.cellPixelSize == PixelSize(width: 8, height: 16))

    controller.pixelSize = PixelSize(width: 10, height: 20)

    #expect(host.graphicsCapabilities.cellPixelSize == PixelSize(width: 10, height: 20))
  }

  @Test("baselineGraphicsCapabilities preserves cached value on transient ioctl failure")
  func baselinePreservesCachedOnFailure() {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0,
      outputFileDescriptor: 1,
      fallbackSize: CellSize(width: 80, height: 24),
      controller: controller
    )
    _ = host.graphicsCapabilities  // prime cache with (8, 16)

    controller.pixelSize = nil

    #expect(host.graphicsCapabilities.cellPixelSize == PixelSize(width: 8, height: 16))
  }

  @Test("HostedRasterSurface reflects updated cellPixelSize")
  @MainActor
  func hostedRasterSurfaceUpdateCellPixelSize() {
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 80, height: 24),
      appearance: .fallback,
      onFrame: { _ in }
    )

    surface.updateSurfaceCapabilities(
      cellPixelSize: PixelSize(width: 12, height: 24),
      pointerInputCapabilities: surface.pointerInputCapabilities
    )

    #expect(surface.graphicsCapabilities.cellPixelSize == PixelSize(width: 12, height: 24))
  }

  @Test("HostedRasterSurface clears cell pixel size on nil update")
  @MainActor
  func hostedRasterSurfaceClearsCellPixelSize() {
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 80, height: 24),
      appearance: .fallback,
      onFrame: { _ in }
    )
    surface.updateSurfaceCapabilities(
      cellPixelSize: PixelSize(width: 10, height: 20),
      pointerInputCapabilities: surface.pointerInputCapabilities
    )

    surface.updateSurfaceCapabilities(
      cellPixelSize: nil,
      pointerInputCapabilities: surface.pointerInputCapabilities
    )

    #expect(surface.graphicsCapabilities.cellPixelSize == nil)
  }

  @Test("HostedRasterSurface carries pointer capabilities beside cellPixelSize")
  @MainActor
  func hostedRasterSurfaceUpdatesPointerCapabilities() {
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 80, height: 24),
      appearance: .fallback,
      onFrame: { _ in }
    )
    let capabilities = PointerInputCapabilities(
      precision: .subCell(
        source: .nativePixels,
        metrics: CellPixelMetrics(width: 12, height: 24, source: .reported)
      ),
      supportsHover: true
    )

    surface.updateSurfaceCapabilities(
      cellPixelSize: PixelSize(width: 12, height: 24),
      pointerInputCapabilities: capabilities
    )

    #expect(surface.graphicsCapabilities.cellPixelSize == PixelSize(width: 12, height: 24))
    #expect(surface.pointerInputCapabilities == capabilities)
  }

  @Test("SIGWINCH-driven refresh surfaces new metrics in the next GeometryReader proxy")
  @MainActor
  func sigwinchRefreshSurfacesInProxy() {
    var environmentValues = EnvironmentValues()
    environmentValues.terminalSize = CellSize(width: 40, height: 10)
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
