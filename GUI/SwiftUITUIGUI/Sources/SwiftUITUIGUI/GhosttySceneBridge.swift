import Foundation
import GhosttyTerminal
import TerminalUI
import TerminalUIScenes
import SwiftUI

@MainActor
final class GhosttySceneBridge {
  final class CallbackRouter: @unchecked Sendable {
    var onInput: ((Data) -> Void)?
    var onResize: ((InMemoryTerminalViewport) -> Void)?
  }

  final class BridgeProxy {
    weak var bridge: GhosttySceneBridge?
  }

  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftUITUISceneDescriptor
  let viewState: TerminalViewState

  private var style: SwiftUITUITerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private let callbackRouter: CallbackRouter
  private let bridgeProxy: BridgeProxy
  private let terminalSession: InMemoryTerminalSession
  private var bufferedOutput: [String] = []
  private var surfaceReady = false
  private var currentColorScheme: SwiftUI.ColorScheme = .light
  private(set) var lastViewportSize: Size?

  init(
    descriptor: SwiftUITUISceneDescriptor,
    style: SwiftUITUITerminalStyle
  ) {
    self.descriptor = descriptor
    self.style = style

    let controller = TerminalController(
      theme: style.terminalTheme,
      terminalConfiguration: style.terminalConfiguration
    )
    viewState = TerminalViewState(controller: controller)
    callbackRouter = CallbackRouter()
    bridgeProxy = BridgeProxy()

    terminalSession = InMemoryTerminalSession(
      write: { [callbackRouter] data in
        callbackRouter.onInput?(data)
      },
      resize: { [callbackRouter] viewport in
        callbackRouter.onResize?(viewport)
      }
    )

    callbackRouter.onInput = { [bridgeProxy] data in
      Task { @MainActor in
        bridgeProxy.bridge?.receiveTerminalInput(Array(data))
      }
    }

    callbackRouter.onResize = { [bridgeProxy] viewport in
      Task { @MainActor in
        bridgeProxy.bridge?.handleSurfaceResize(viewport)
      }
    }

    viewState.configuration = TerminalSurfaceOptions(
      backend: .inMemory(terminalSession),
      fontSize: style.fontSize,
      context: .window
    )
    bridgeProxy.bridge = self
  }

  func attach(session: any HostedSceneSessionHandling) {
    self.session = session
  }

  func startSession() async throws -> RunLoopExitReason {
    guard let session else {
      throw BridgeError.missingSession
    }
    return try await session.start()
  }

  func stopSession() {
    session?.stop()
  }

  func receiveTerminalInput(_ bytes: [UInt8]) {
    session?.sendInput(bytes)
  }

  func apply(style: SwiftUITUITerminalStyle) {
    self.style = style
    viewState.controller.setTheme(style.terminalTheme)
    viewState.controller.setTerminalConfiguration(style.terminalConfiguration)
    viewState.configuration = TerminalSurfaceOptions(
      backend: .inMemory(terminalSession),
      fontSize: style.fontSize,
      context: .window
    )
    updateAppearance(currentColorScheme)
  }

  func updateAppearance(_ colorScheme: SwiftUI.ColorScheme) {
    currentColorScheme = colorScheme
    guard let session else {
      return
    }
    session.updateAppearance(
      style.terminalAppearance(for: colorScheme.terminalUIScheme)
    )
  }

  func receiveOutput(_ output: String) {
    if surfaceReady {
      terminalSession.receive(output)
    } else {
      bufferedOutput.append(output)
    }
  }

  func handleSurfaceResize(_ viewport: InMemoryTerminalViewport) {
    surfaceReady = true
    let size = Size(
      width: Int(viewport.columns),
      height: Int(viewport.rows)
    )
    lastViewportSize = size
    session?.resize(to: size)
    flushBufferedOutput()
  }

  private func flushBufferedOutput() {
    guard surfaceReady, !bufferedOutput.isEmpty else {
      return
    }

    let chunks = bufferedOutput
    bufferedOutput.removeAll(keepingCapacity: true)
    for chunk in chunks {
      terminalSession.receive(chunk)
    }
  }
}

@MainActor
protocol HostedSceneSessionHandling: AnyObject {
  func start() async throws -> RunLoopExitReason
  func sendInput(_ bytes: [UInt8])
  func resize(to size: Size)
  func updateAppearance(_ appearance: TerminalAppearance)
  func stop()
}

extension HostedSceneSession: HostedSceneSessionHandling {}

private extension SwiftUI.ColorScheme {
  var terminalUIScheme: TerminalUI.ColorScheme {
    switch self {
    case .light:
      return .light
    case .dark:
      return .dark
    @unknown default:
      return .light
    }
  }
}
