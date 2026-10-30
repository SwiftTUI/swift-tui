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
    func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
      TerminalModeSnapshot()
    }
    func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}
    func windowSize(of _: Int32) throws -> CellSize { CellSize(width: 80, height: 24) }
    func cellPixelSize(of _: Int32) throws -> PixelSize? { pixelSize }
    func write(_: String, to _: Int32) throws {}
    func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
  }

  @Test("pixel mouse coordinates refresh after terminal font changes")
  func mouseMetricsRefresh() throws {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0, outputFileDescriptor: 1, fallbackSize: .init(width: 80, height: 24),
      controller: controller, environment: ["TERM": "xterm-256color"],
      mouseInputResolution: .automatic(.assumeWhenCellMetricsKnown))
    try host.enableRawMode()
    defer { try? host.disableRawMode() }
    let original = host.resolvedInputCapabilities
    controller.pixelSize = .init(width: 16, height: 32)
    let updated = host.resolvedInputCapabilities
    #expect(updated != original)
    #expect(
      updated.mouseCoordinateMode
        == .pixels(
          metrics: .init(width: 16, height: 32, source: .reported), source: .terminalPixels))
    var parser = TerminalInputParser(mouseCoordinateMode: original.mouseCoordinateMode)
    #expect(parser.feed(Array("\u{001B}[<0;".utf8)).isEmpty)
    parser.updateMouseCoordinateMode(updated.mouseCoordinateMode)
    let event = try #require(parser.feed(Array("33;65M".utf8)).first)
    guard case .mouse(let mouse) = event else {
      Issue.record("expected mouse input")
      return
    }
    #expect(mouse.location.cell == .init(x: 2, y: 2))
    controller.pixelSize = nil
    #expect(host.resolvedInputCapabilities == updated)
  }

  @Test("frame acquisition synchronizes refreshed mouse metrics into the input reader")
  @MainActor
  func frameRefreshesInputReader() throws {
    let controller = MutableController()
    let host = TerminalHost(
      inputFileDescriptor: 0, outputFileDescriptor: 1,
      fallbackSize: .init(width: 80, height: 24), controller: controller,
      environment: ["TERM": "xterm-256color"],
      mouseInputResolution: .automatic(.assumeWhenCellMetricsKnown))
    try host.enableRawMode()
    defer { try? host.disableRawMode() }
    let reader = RefreshInputReader()
    let root = testIdentity("RefreshMetrics")
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: host, terminalInputReader: reader,
      scheduler: FrameScheduler(), stateContainer: StateContainer(initialState: 0),
      focusTracker: FocusTracker(), viewBuilder: { _, _ in Text("metrics") })
    let frame = ScheduledFrame(
      causes: [.input], invalidatedIdentities: [], signalNames: [],
      externalReasons: [], triggeredDeadline: nil, nextDeadline: nil)
    _ = loop.resolveContext(for: frame)
    let initial = reader.capabilities.value
    controller.pixelSize = .init(width: 12, height: 24)
    _ = loop.resolveContext(for: frame)
    #expect(reader.capabilities.value != initial)
    #expect(reader.capabilities.value == host.resolvedInputCapabilities)
  }

  private final class RefreshInputReader: TerminalInputReading, TerminalInputCapabilityConfiguring {
    let capabilities = LockedBox(ResolvedTerminalInputCapabilities())
    func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
    func updateInputCapabilities(_ value: ResolvedTerminalInputCapabilities) {
      capabilities.value = value
    }
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
