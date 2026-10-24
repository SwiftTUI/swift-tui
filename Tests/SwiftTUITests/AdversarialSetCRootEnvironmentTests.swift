@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCRootEnvironmentTests {
  @Test func setC139ParagraphSpacingChangeReflows() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC139") {
      VStack(alignment: .leading, spacing: 0) {
        SetCParagraphReader().equatable()
        Text("root")
      }
    }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(SetCRootEnvironment.row(of: "after", in: host.frame) == 1, "\(host.frame)")
    host.configuration = SetCRootEnvironment.configuration(paragraphSpacing: 1)
    try SetCRootEnvironment.wake(loop)
    #expect(SetCRootEnvironment.row(of: "after", in: host.frame) == 2, "\(host.frame)")
  }

  @Test func setC140ThemeChangeForcesRoot() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC140") { SetCEnvironmentRoot() }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(host.frame.contains("theme none"), "\(host.frame)")
    host.configuration = SetCRootEnvironment.configuration(theme: .default)
    try SetCRootEnvironment.wake(loop)
    #expect(host.frame.contains("theme set"), "\(host.frame)")
  }

  @Test func setC141CellPixelMetricsChangeForcesRoot() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC141") { SetCEnvironmentRoot() }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(host.frame.contains("metrics estimated"), "\(host.frame)")
    host.configuration = SetCRootEnvironment.configuration(
      graphics: TerminalGraphicsCapabilities(cellPixelSize: PixelSize(width: 8, height: 16)))
    try SetCRootEnvironment.wake(loop)
    #expect(host.frame.contains("metrics reported"), "\(host.frame)")
  }

  @Test func setC142PointerCapabilitiesChangeForcesRoot() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC142") { SetCEnvironmentRoot() }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(host.frame.contains("hover no"), "\(host.frame)")
    var pointer = PointerInputCapabilities.cellOnly
    pointer.supportsHover = true
    host.configuration = SetCRootEnvironment.configuration(pointer: pointer)
    try SetCRootEnvironment.wake(loop)
    #expect(host.frame.contains("hover yes"), "\(host.frame)")
  }

  @Test func setC143ReduceMotionChangeForcesRoot() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC143") { SetCEnvironmentRoot() }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(host.frame.contains("motion full"), "\(host.frame)")
    host.configuration = SetCRootEnvironment.configuration(
      accessibility: AccessibilityPreferences(reduceMotion: true))
    try SetCRootEnvironment.wake(loop)
    #expect(host.frame.contains("motion reduced"), "\(host.frame)")
  }

  @Test func setC144TerminalSizeChangeForcesRoot() throws {
    let host = SetCHostSurface(SetCRootEnvironment.configuration())
    let loop = try SetCRootEnvironment.loop(host, name: "setC144") { SetCEnvironmentRoot() }
    defer { loop.lifecycleCoordinator.shutdown() }
    try #require(host.frame.contains("width 40"), "\(host.frame)")
    host.configuration = SetCRootEnvironment.configuration(size: CellSize(width: 50, height: 6))
    try SetCRootEnvironment.wake(loop)
    #expect(host.frame.contains("width 50"), "\(host.frame)")
  }
}

private struct SetCEnvironmentRoot: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SetCEnvironmentReader().equatable()
      Text("root")
    }
  }
}

/// Always-equal boundary: only a root-forced frame can refresh the readers.
private struct SetCEnvironmentReader: View, @MainActor Equatable {
  @Environment(\.theme) private var theme
  @Environment(\.cellPixelMetrics) private var metrics
  @Environment(\.pointerInputCapabilities) private var pointer
  @Environment(\.renderingReduceMotion) private var reduceMotion
  @Environment(\.terminalSize) private var size

  static func == (lhs: Self, rhs: Self) -> Bool { true }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("theme \(theme == nil ? "none" : "set")")
      Text("metrics \(metrics.source == .reported ? "reported" : "estimated")")
      Text("hover \(pointer.supportsHover ? "yes" : "no")")
      Text("motion \(reduceMotion ? "reduced" : "full")")
      Text("width \(size.width)")
    }
  }
}

private struct SetCParagraphReader: View, @MainActor Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool { true }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("para one").paragraph()
      Text("after")
    }
  }
}

private final class SetCHostSurface: PresentationSurface, HostGeometryPresentationSurface {
  var configuration: HostLayoutConfiguration
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  private(set) var frame = ""

  init(_ configuration: HostLayoutConfiguration) {
    self.configuration = configuration
  }

  var surfaceSize: CellSize { configuration.size }
  var appearance: TerminalAppearance { configuration.appearance }
  var theme: Theme? { configuration.theme }
  var graphicsCapabilities: TerminalGraphicsCapabilities { configuration.graphics }
  var pointerInputCapabilities: PointerInputCapabilities { configuration.pointer }

  func captureHostLayoutConfiguration() -> HostLayoutConfiguration { configuration }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ output: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to point: CellPoint) throws {}

  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frame = surface.lines.joined(separator: "\n")
    return TerminalPresentationMetrics(
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height, strategy: .fullRepaint)
  }
}

private final class SetCHostInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

@MainActor
private enum SetCRootEnvironment {
  static func configuration(
    size: CellSize = CellSize(width: 40, height: 6),
    theme: Theme? = nil,
    graphics: TerminalGraphicsCapabilities = .none,
    pointer: PointerInputCapabilities = .cellOnly,
    accessibility: AccessibilityPreferences = .init(),
    paragraphSpacing: Int = 0
  ) -> HostLayoutConfiguration {
    HostLayoutConfiguration(
      size: size, appearance: .fallback, theme: theme, graphics: graphics, pointer: pointer,
      accessibilityPreferences: accessibility, paragraphSpacing: paragraphSpacing)
  }

  static func loop<V: View>(
    _ host: SetCHostSurface, name: String, @ViewBuilder content: @escaping () -> V
  ) throws -> SwiftTUIRuntime.RunLoop<Int, V> {
    let identity = testIdentity(name)
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: identity, presentationSurface: host,
      terminalInputReader: SetCHostInput(),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [identity]),
      focusTracker: FocusTracker(invalidationIdentities: [identity])
    ) { _, _ in content() }
    try wake(loop)
    loop.renderer.enableSelectiveEvaluation()
    return loop
  }

  /// The host-geometry wake: the run loop re-reads the surface configuration.
  static func wake<V: View>(_ loop: SwiftTUIRuntime.RunLoop<Int, V>) throws {
    loop.scheduler.requestSignal(named: "SIGWINCH")
    var rendered = 0
    try loop.renderPendingFrames(renderedFrames: &rendered)
  }

  static func row(of text: String, in frame: String) -> Int? {
    frame.split(separator: "\n", omittingEmptySubsequences: false)
      .firstIndex { $0.contains(text) }
  }
}
