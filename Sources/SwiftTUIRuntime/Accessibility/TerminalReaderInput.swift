import Foundation
import SwiftTUICore

@MainActor
package final class TerminalReaderInput: @preconcurrency TerminalInputReading,
  @preconcurrency TerminalInputCapabilityConfiguring, TerminalInputHandoffSuspending
{
  private let source: any TerminalInputReading
  private nonisolated let handoff: (any TerminalInputHandoffSuspending)?
  private let surface: TerminalReaderSurface
  private var line = ""
  private var rejectedLine = false
  package weak var sceneHub: TerminalReaderSceneHub?

  package init(source: any TerminalInputReading, surface: TerminalReaderSurface) {
    self.source = source
    handoff = source as? any TerminalInputHandoffSuspending
    self.surface = surface
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    let events = source.inputEvents()
    return AsyncStream { continuation in
      let task = Task { @MainActor [weak self] in
        for await event in events {
          guard !Task.isCancelled, let self else { break }
          do {
            let result = try process(event)
            for input in result.events { continuation.yield(input) }
            if result.exit { break }
          } catch {
            // End the input stream so the run loop performs normal terminal restoration.
            break
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  package func process(_ event: InputEvent) throws -> (events: [InputEvent], exit: Bool) {
    if case .key(let press) = event, press.key == .functionKey(12) {
      line = ""
      rejectedLine = false
      sceneHub?.reset()
      try surface.setReading(!surface.isReading)
      updateInputCapabilities(surface.resolvedInputCapabilities)
      return ([], false)
    }
    guard surface.isReading else { return ([event], false) }
    let surface = sceneHub?.selectedSurface ?? self.surface
    switch event {
    case .key(let press):
      if press.modifiers.contains(.ctrl), case .character(let char) = press.key {
        if char == "c" || (char == "d" && line.isEmpty) {
          line = ""
          surface.commands.editor = nil
          try surface.emit("\nReturn to shell.")
          return ([], true)
        }
        if char == "u" {
          line = ""
          rejectedLine = false
          surface.commandIsBeingTyped = false
          try surface.emit("\nCommand cleared.")
          try surface.prompt()
        }
        return ([], false)
      }
      switch press.key {
      case .return:
        try surface.echo("\r\n")
        if rejectedLine {
          line = ""
          rejectedLine = false
          surface.commandIsBeingTyped = false
          try surface.emit(
            "Command exceeded 65536 UTF-8 bytes and was discarded. Use smaller edits.")
          try surface.prompt()
          return ([], false)
        }
        if line == "scenes", let sceneHub {
          line = ""
          surface.commandIsBeingTyped = false
          try surface.emit(sceneHub.listing)
          try surface.prompt()
          return ([], false)
        }
        if line.hasPrefix("scene "), let sceneHub {
          let message = sceneHub.select(String(line.dropFirst(6)))
          line = ""
          let selected = sceneHub.selectedSurface ?? surface
          try selected.emit(message)
          try selected.prompt()
          return ([], false)
        }
        let current = surface.commands.model.current
        let result = surface.commands.command(line)
        line = ""
        surface.commandIsBeingTyped = false
        try surface.emit(result.output)
        if result.exit { return ([], true) }
        if result.grid {
          sceneHub?.reset()
          try self.surface.setReading(false)
          return ([], false)
        }
        try surface.prompt()
        var requests = result.request.map { [InputEvent.accessibility($0)] } ?? []
        if current != surface.commands.model.current,
          let node = surface.commands.model.currentChunk?.node,
          node.control?.actions.contains(.accessibilityFocus) == true,
          let target = node.actionTarget
        {
          requests.append(.accessibility(.init(target: target, action: .accessibilityFocus)))
        }
        return (sceneHub?.route(requests) ?? requests, false)
      case .escape:
        line = ""
        rejectedLine = false
        surface.commandIsBeingTyped = false
        surface.commands.editor = nil
        try surface.emit("\nCommand and draft canceled.")
        try surface.prompt()
      case .backspace, .delete:
        if !line.isEmpty {
          line.removeLast()
          if !surface.commands.protectsInput { try surface.echo("\u{8} \u{8}") }
        }
        surface.commandIsBeingTyped = !line.isEmpty
      case .character(let char): try append(String(char))
      case .space: try append(" ")
      default: break
      }
    case .paste(let paste):
      // A paste is data in one command, never a sequence of automatically executed commands.
      guard paste.content.utf8.count <= 65_536 else {
        rejectedLine = true
        return ([], false)
      }
      let value = TerminalReaderModel.safe(paste.content, limit: 65_536)
        .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
      try append(value)
    default: break
    }
    return ([], false)
  }

  private func append(_ text: String) throws {
    let surface = sceneHub?.selectedSurface ?? self.surface
    guard !rejectedLine else { return }
    guard line.utf8.count + text.utf8.count <= 65_536 else {
      rejectedLine = true
      return
    }
    guard text.unicodeScalars.allSatisfy({ $0.value >= 32 && !(127...159).contains($0.value) })
    else { return }
    line += text
    surface.commandIsBeingTyped = true
    if !surface.commands.protectsInput {
      try surface.echo(TerminalReaderModel.safe(text, limit: 65_536))
    }
  }

  package func updateInputCapabilities(_ capabilities: ResolvedTerminalInputCapabilities) {
    (source as? any TerminalInputCapabilityConfiguring)?.updateInputCapabilities(capabilities)
  }
  package nonisolated func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    if let handoff { return try handoff.withInputSuspended(body) }
    return try body()
  }
  package func withInputSuspended<T: Sendable>(
    _ body: @MainActor @Sendable () async throws -> T
  ) async rethrows -> T {
    if let handoff { return try await handoff.withInputSuspended(body) }
    return try await body()
  }
}

extension SceneSessionResources {
  @MainActor
  package func withTerminalReader() -> SceneSessionResources {
    let surface = TerminalReaderSurface(
      terminal: presentationSurface,
      enabled: runtimeConfiguration.terminalReader)
    let resources = SceneSessionResources(
      presentationSurface: surface,
      terminalInputReader: TerminalReaderInput(source: terminalInputReader, surface: surface),
      signalReader: signalReader, scheduler: scheduler, surfaceName: surfaceName,
      environmentValues: environmentValues, frameSink: frameSink, progressProbe: progressProbe,
      runtimeConfiguration: runtimeConfiguration, renderMode: renderMode,
      focusPresentationHandler: focusPresentationHandler)
    resources.runtimeIssueSink = runtimeIssueSink
    return resources
  }
}
