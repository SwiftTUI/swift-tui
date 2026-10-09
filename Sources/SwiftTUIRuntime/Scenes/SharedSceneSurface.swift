import SwiftTUICore

/// One layout and semantic graph, presented to the terminal and its browser companion.
/// Owned by the scene's main-actor runtime, like TerminalHost itself.
package final class SharedSceneSurface: HostGeometryPresentationSurface,
  SemanticHostFramePresentationSurface, TerminalCommandPresentationSurface,
  TerminalCursorFocusPresentationSurface, TerminalInputCapabilityProviding,
  ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface,
  TerminalReaderResponseReceiving
{
  package let terminal: any PresentationSurfaceMetricsProvider
  package private(set) var terminalIsAttached: Bool
  private let toleratesTerminalDetach: Bool
  private var rawModeRequested = false
  private var browser: (any SemanticHostFramePresentationSurface)?
  private var browserIsConnected: () -> Bool = { false }
  private var lastGrid: CellSize?
  private var viewportRevision: UInt64 = 1
  private var repaintTerminal = true

  package init(
    terminal: any PresentationSurfaceMetricsProvider,
    terminalIsAttached: Bool,
    toleratesTerminalDetach: Bool = false
  ) {
    self.terminal = terminal
    self.terminalIsAttached = terminalIsAttached
    self.toleratesTerminalDetach = toleratesTerminalDetach
  }

  package func attachBrowser(
    _ surface: any SemanticHostFramePresentationSurface,
    isConnected: @escaping () -> Bool
  ) {
    browser = surface
    browserIsConnected = isConnected
  }

  package func setTerminalAttached(_ attached: Bool) throws {
    guard attached != terminalIsAttached else { return }
    terminalIsAttached = attached
    repaintTerminal = true
    guard rawModeRequested else { return }
    if attached {
      try terminalCommands?.enableRawMode()
    } else {
      try? terminalCommands?.disableRawMode()
    }
  }

  private var terminalCommands: (any TerminalCommandPresentationSurface)? {
    terminal as? any TerminalCommandPresentationSurface
  }

  package var surfaceSize: CellSize { captureHostLayoutConfiguration().size }
  package var capabilityProfile: TerminalCapabilityProfile {
    terminalIsAttached
      ? terminal.capabilityProfile : browser?.capabilityProfile ?? terminal.capabilityProfile
  }
  package var appearance: TerminalAppearance { captureHostLayoutConfiguration().appearance }
  package var theme: Theme? { captureHostLayoutConfiguration().theme }
  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    captureHostLayoutConfiguration().graphics
  }
  package var pointerInputCapabilities: PointerInputCapabilities {
    captureHostLayoutConfiguration().pointer
  }
  package var supportsUserExit: Bool { terminalIsAttached && terminal.supportsUserExit }
  package var resolvedInputCapabilities: ResolvedTerminalInputCapabilities {
    (terminal as? any TerminalInputCapabilityProviding)?.resolvedInputCapabilities ?? .init()
  }

  package func captureHostLayoutConfiguration() -> HostLayoutConfiguration {
    let local = terminal.hostLayoutConfiguration()
    let remote = browser?.hostLayoutConfiguration()
    let connected = browserIsConnected()
    let presentation = connected ? remote ?? local : local
    var size = terminalIsAttached ? local.size : remote?.size ?? local.size
    if terminalIsAttached, connected, let remote {
      // The common grid fits both viewports. Browser enlargement can reflow it,
      // but can never expand terminal output beyond the physical terminal.
      size = .init(
        width: min(size.width, remote.size.width), height: min(size.height, remote.size.height))
    }
    if let lastGrid, lastGrid != size {
      viewportRevision += 1
      repaintTerminal = true
    }
    lastGrid = size
    let geometry = remote?.geometry.map {
      HostGeometryStamp(
        session: $0.session, revision: $0.revision, viewportRevision: viewportRevision)
    }
    return .init(
      size: size, appearance: presentation.appearance, theme: presentation.theme,
      graphics: terminalIsAttached ? local.graphics : presentation.graphics,
      pointer: presentation.pointer, geometry: geometry,
      reduceMotion: presentation.reduceMotion,
      accessibilityPreferences: presentation.accessibilityPreferences,
      paragraphSpacing: connected ? presentation.paragraphSpacing : local.paragraphSpacing)
  }

  package func enableRawMode() throws {
    rawModeRequested = true
    if terminalIsAttached { try terminalCommands?.enableRawMode() }
  }
  package func disableRawMode() throws {
    rawModeRequested = false
    if terminalIsAttached { try terminalCommands?.disableRawMode() }
  }
  package func write(_ output: String) throws {
    if terminalIsAttached { try terminalCommands?.write(output) }
  }
  package func clearScreen() throws {
    if terminalIsAttached { try terminalCommands?.clearScreen() }
  }
  package func moveCursor(to point: CellPoint) throws {
    if terminalIsAttached { try terminalCommands?.moveCursor(to: point) }
  }
  package func setPointerHoverEnabled(_ enabled: Bool) throws {
    if terminalIsAttached { try terminalCommands?.setPointerHoverEnabled(enabled) }
  }

  @discardableResult
  package func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    var metrics =
      try browser?.present(frame)
      ?? .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
    guard terminalIsAttached else {
      if let reader = terminal as? TerminalReaderSurface {
        _ = try reader.present(frame, terminalAttached: false)
      }
      return metrics
    }
    do {
      if let target = terminal as? any SemanticHostFramePresentationSurface {
        var terminalFrame = frame
        if repaintTerminal { terminalFrame.rasterDamage = nil }
        metrics = try target.present(terminalFrame)
      } else if let target = terminal as? any DamageAwarePresentationSurface {
        metrics = try target.present(
          frame.raster, damage: repaintTerminal ? nil : frame.rasterDamage)
      } else if let target = terminal as? any RasterPresentationSurface {
        metrics = try target.present(frame.raster)
      }
      repaintTerminal = false
    } catch {
      guard toleratesTerminalDetach else { throw error }
      try? setTerminalAttached(false)
    }
    return metrics
  }

  @discardableResult
  package func receiveReaderResponse(_ response: AccessibilityActionResponse) -> Bool {
    (terminal as? any TerminalReaderResponseReceiving)?.receiveReaderResponse(response) ?? false
  }

  @MainActor @discardableResult
  package func writeClipboard(_ text: String) throws -> Bool {
    if InputDispatchContext.origin == .terminal,
      let reader = terminal as? TerminalReaderSurface, reader.externalReaderOutput != nil
    {
      return try reader.writeClipboard(text)
    }
    if InputDispatchContext.origin == .browser || !terminalIsAttached {
      return try (browser as? any ClipboardWritingPresentationSurface)?.writeClipboard(text)
        ?? false
    }
    return try (terminal as? any ClipboardWritingPresentationSurface)?.writeClipboard(text) ?? false
  }

  @MainActor
  package func readClipboard() throws -> String? {
    // Browser paste arrives from that browser. Never read the server's clipboard
    // on behalf of an attached browser or a task launched by its input.
    guard InputDispatchContext.origin != .browser else { return nil }
    if let reader = terminal as? TerminalReaderSurface, reader.externalReaderOutput != nil {
      return try reader.readClipboard()
    }
    guard terminalIsAttached else { return nil }
    return try (terminal as? any ClipboardReadingPresentationSurface)?.readClipboard()
  }
}
