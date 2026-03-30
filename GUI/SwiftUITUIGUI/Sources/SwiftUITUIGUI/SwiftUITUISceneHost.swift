import Observation
import GhosttyTerminal
import TerminalUI
import TerminalUIScenes
import SwiftUI

@MainActor
@Observable
public final class SwiftUITUISceneHost {
  public let descriptor: SwiftUITUISceneDescriptor

  public private(set) var isRunning = false
  public private(set) var lastError: String?

  @ObservationIgnored
  private let bridge: GhosttySceneBridge

  @ObservationIgnored
  private var startTask: Task<Void, Never>?

  public init<A: TerminalUI.App>(
    app: A,
    descriptor: SwiftUITUISceneDescriptor,
    style: SwiftUITUITerminalStyle
  ) throws {
    self.descriptor = descriptor
    bridge = GhosttySceneBridge(
      descriptor: descriptor,
      style: style
    )

    let session = try MultiSceneLauncher.makeHostedSceneSession(
      for: app,
      sceneID: descriptor.id,
      initialSize: .init(width: 80, height: 24),
      appearance: style.terminalAppearance(for: TerminalUI.ColorScheme.light),
      onOutput: { [weak bridge] output in
        Task { @MainActor [weak bridge] in
          bridge?.receiveOutput(output)
        }
      }
    )
    bridge.attach(session: session)
  }

  public var viewState: TerminalViewState {
    bridge.viewState
  }

  public func start() {
    guard startTask == nil else {
      return
    }

    isRunning = true
    lastError = nil
    startTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      do {
        _ = try await bridge.startSession()
      } catch {
        lastError = error.localizedDescription
      }

      isRunning = false
      startTask = nil
    }
  }

  public func stop() {
    startTask?.cancel()
    startTask = nil
    bridge.stopSession()
    isRunning = false
  }

  public func apply(style: SwiftUITUITerminalStyle) {
    bridge.apply(style: style)
  }

  public func updateAppearance(_ colorScheme: SwiftUI.ColorScheme) {
    bridge.updateAppearance(colorScheme)
  }

  var bridgeForTesting: GhosttySceneBridge {
    bridge
  }
}
