import Foundation
import SwiftTUICore

/// In-process acknowledgements cannot be overwritten by a browser action in the same frame.
package protocol TerminalReaderResponseReceiving: AnyObject {
  @discardableResult func receiveReaderResponse(_ response: AccessibilityActionResponse) -> Bool
}

/// Presentation-only wrapper. The existing run loop continues to own state and dispatch.
package final class TerminalReaderSurface: HostGeometryPresentationSurface,
  SemanticHostFramePresentationSurface, TerminalCommandPresentationSurface,
  TerminalCursorFocusPresentationSurface, TerminalInputCapabilityProviding,
  ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface,
  TerminalReaderResponseReceiving
{
  package let terminal: any PresentationSurfaceMetricsProvider
  package var commands = TerminalReaderCommands()
  package private(set) var isReading: Bool
  package var commandIsBeingTyped = false
  package var externalReaderOutput: (any TerminalCommandPresentationSurface)?
  package var suppressReaderPresentation = false
  private var queuedNotices: [String] = []
  private var response: AccessibilityActionResponse?
  private var lastFrame: SemanticHostFrame?
  private var started = false

  package init(terminal: any PresentationSurfaceMetricsProvider, enabled: Bool) {
    self.terminal = terminal
    isReading = enabled
    #if !canImport(WASILibc)
      (terminal as? TerminalHost)?.readerMode = enabled
    #endif
  }

  package var surfaceSize: CellSize { terminal.surfaceSize }
  package var capabilityProfile: TerminalCapabilityProfile { terminal.capabilityProfile }
  package var appearance: TerminalAppearance { terminal.appearance }
  package var theme: Theme? { terminal.theme }
  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    isReading ? .none : terminal.graphicsCapabilities
  }
  package var pointerInputCapabilities: PointerInputCapabilities {
    terminal.pointerInputCapabilities
  }
  package var supportsUserExit: Bool { terminal.supportsUserExit }
  package var resolvedInputCapabilities: ResolvedTerminalInputCapabilities {
    (terminal as? any TerminalInputCapabilityProviding)?.resolvedInputCapabilities ?? .init()
  }
  private var output: (any TerminalCommandPresentationSurface)? {
    externalReaderOutput ?? terminal as? any TerminalCommandPresentationSurface
  }
  package func captureHostLayoutConfiguration() -> HostLayoutConfiguration {
    terminal.hostLayoutConfiguration()
  }

  package func enableRawMode() throws {
    if !started {
      try output?.write(
        "Terminal reader available: start with --reader or press F12 in the running app.\r\n")
    }
    try output?.enableRawMode()
    started = true
    if isReading { try emit("Sequential terminal reader. Type help then Enter for commands.") }
  }
  package func disableRawMode() throws {
    commands.editor = nil
    try output?.disableRawMode()
  }
  package func write(_ text: String) throws { if !isReading { try output?.write(text) } }
  package func clearScreen() throws { if !isReading { try output?.clearScreen() } }
  package func moveCursor(to point: CellPoint) throws {
    if !isReading { try output?.moveCursor(to: point) }
  }
  package func setPointerHoverEnabled(_ enabled: Bool) throws {
    if !isReading { try output?.setPointerHoverEnabled(enabled) }
  }
  package func presentAccessibilityCursorFocus(at point: CellPoint?) throws {
    if !isReading {
      try (terminal as? any TerminalCursorFocusPresentationSurface)?
        .presentAccessibilityCursorFocus(at: point)
    }
  }

  package func setReading(_ enabled: Bool) throws {
    guard enabled != isReading else { return }
    commands.editor = nil
    commandIsBeingTyped = false
    #if !canImport(WASILibc)
      if let host = terminal as? TerminalHost {
        try host.setReaderMode(enabled)
      } else {
        try output?.disableRawMode()
        if !enabled { try output?.enableRawMode() }
      }
    #else
      try output?.disableRawMode()
      if !enabled { try output?.enableRawMode() }
    #endif
    isReading = enabled
    if enabled {
      try emit("Sequential terminal reader. Type help for commands.\n" + commands.model.read())
      try prompt()
    } else if var frame = lastFrame {
      frame.rasterDamage = nil
      _ = try presentRaster(frame)
    }
  }

  @discardableResult
  package func receiveReaderResponse(_ response: AccessibilityActionResponse) -> Bool {
    guard commands.pendingRequest?.requestID == response.requestID,
      commands.pendingRequest?.target == response.target
    else { return false }
    self.response = response
    return true
  }

  @discardableResult
  package func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    try present(frame, terminalAttached: true)
  }

  @discardableResult
  package func present(_ frame: SemanticHostFrame, terminalAttached: Bool) throws
    -> PresentationMetrics
  {
    let first = lastFrame == nil
    lastFrame = frame
    let notices = commands.model.update(frame)
    if let response,
      let acknowledgement = commands.acknowledge(response)
    {
      self.response = nil
      queuedNotices.append(acknowledgement)
    }
    if !suppressReaderPresentation
      && (externalReaderOutput != nil || (terminalAttached && isReading))
    {
      if first {
        try emit(commands.model.read())
        try prompt()
      }
      queuedNotices += notices
      if queuedNotices.count > 128 { queuedNotices = Array(queuedNotices.suffix(128)) }
      if !commandIsBeingTyped && commands.editor == nil { try flushNotices() }
      return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
    }
    return terminalAttached && !isReading
      ? try presentRaster(frame)
      : .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }

  private func presentRaster(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    if let target = terminal as? any DamageAwarePresentationSurface {
      return try target.present(frame.raster, damage: frame.rasterDamage)
    }
    if let target = terminal as? any RasterPresentationSurface {
      return try target.present(frame.raster)
    }
    return .rasterHostMetrics(for: frame.raster, damage: frame.rasterDamage)
  }

  package func flushNotices() throws {
    guard !queuedNotices.isEmpty else { return }
    try output?.write("\r\n")
    for notice in queuedNotices { try emit(notice) }
    queuedNotices.removeAll(keepingCapacity: true)
    try prompt()
  }
  package func emit(_ text: String) throws {
    guard !text.isEmpty else { return }
    try output?.write(text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
  }
  package func echo(_ text: String) throws { try output?.write(text) }
  package func prompt() throws {
    try output?.write(commands.protectsInput ? "Protected command: " : "Command: ")
  }

  @MainActor @discardableResult
  package func writeClipboard(_ text: String) throws -> Bool {
    if let externalReaderOutput {
      return try (externalReaderOutput as? any ClipboardWritingPresentationSurface)?.writeClipboard(
        text) ?? false
    }
    return try (terminal as? any ClipboardWritingPresentationSurface)?.writeClipboard(text) ?? false
  }
  @MainActor package func readClipboard() throws -> String? {
    if let externalReaderOutput {
      return try (externalReaderOutput as? any ClipboardReadingPresentationSurface)?.readClipboard()
    }
    return try (terminal as? any ClipboardReadingPresentationSurface)?.readClipboard()
  }
}
