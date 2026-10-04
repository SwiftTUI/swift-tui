import SwiftTUIViews

/// Attachment point for presentation and input, never a second graph owner.
@MainActor
package final class SharedSceneEndpoint {
  package let descriptor: SceneDescriptor
  package let surface: SharedSceneSurface
  package let input: SharedSceneInputReader
  package let browserSignals: InProcessSignalReader
  package let resources: SceneSessionResources

  package init(descriptor: SceneDescriptor, resources: SceneSessionResources, isPrimary: Bool) {
    self.descriptor = descriptor
    surface = SharedSceneSurface(
      terminal: resources.presentationSurface, terminalIsAttached: isPrimary,
      toleratesTerminalDetach: !isPrimary)
    input = SharedSceneInputReader(
      terminal: resources.terminalInputReader, attached: isPrimary, endsSession: isPrimary)
    browserSignals = InProcessSignalReader()
    self.resources = SceneSessionResources(
      presentationSurface: surface, terminalInputReader: input,
      signalReader: SharedSceneSignalReader(
        terminal: resources.signalReader, browser: browserSignals),
      scheduler: resources.scheduler, surfaceName: resources.surfaceName,
      environmentValues: resources.environmentValues, frameSink: resources.frameSink,
      progressProbe: resources.progressProbe, runtimeConfiguration: resources.runtimeConfiguration,
      renderMode: resources.renderMode, focusPresentationHandler: resources.focusPresentationHandler
    )
    self.resources.runtimeIssueSink = resources.runtimeIssueSink
  }

  package func setTerminalAttached(_ attached: Bool) throws {
    try surface.setTerminalAttached(attached)
    input.updateInputCapabilities(surface.resolvedInputCapabilities)
    input.setTerminalAttached(attached)
    browserSignals.send("SIGWINCH")
  }

  package func stop() {
    input.finish()
    browserSignals.finish()
  }
}

@MainActor
private final class SharedSceneSignalReader: @preconcurrency SignalSourceArming {
  private let terminal: (any SignalReading)?
  private let browser: InProcessSignalReader

  init(terminal: (any SignalReading)?, browser: InProcessSignalReader) {
    self.terminal = terminal
    self.browser = browser
  }

  @MainActor func armSignalSources() async {
    if let source = terminal as? any SignalSourceArming { await source.armSignalSources() }
  }

  func events() -> AsyncStream<String> {
    let sources = [terminal?.events(), browser.events()].compactMap { $0 }
    return AsyncStream { continuation in
      let tasks = sources.map { source in
        Task { @MainActor in
          for await signal in source { continuation.yield(signal) }
        }
      }
      continuation.onTermination = { _ in for task in tasks { task.cancel() } }
    }
  }
}

/// The companion owns its listener; the terminal continues to own all graphs.
package struct SharedSceneCompanionSession: Sendable {
  package let url: String
  package let stop: @Sendable () async -> Void
  package init(url: String, stop: @escaping @Sendable () async -> Void) {
    self.url = url
    self.stop = stop
  }
}
