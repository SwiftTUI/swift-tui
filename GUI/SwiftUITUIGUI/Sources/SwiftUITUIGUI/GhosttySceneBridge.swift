import Foundation
import GhosttyTerminal
import SwiftUI
import TerminalUI

@MainActor
final class GhosttySceneBridge {
  actor CallbackRouter {
    weak var bridge: GhosttySceneBridge?

    init(bridge: GhosttySceneBridge) {
      self.bridge = bridge
    }

    func handleInput(_ data: Data) async {
      await bridge?.receiveTerminalInput(Array(data))
    }

    func handleResize(_ viewport: InMemoryTerminalViewport) async {
      await bridge?.handleSurfaceResize(viewport)
    }
  }

  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftUITUISceneDescriptor
  let viewState: TerminalViewState

  private var style: SwiftUITUITerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private let callbackRouter: CallbackRouter
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
    callbackRouter = CallbackRouter(bridge: self)

    terminalSession = InMemoryTerminalSession(
      write: { [callbackRouter] data in
        Task {
          await callbackRouter.handleInput(data)
        }
      },
      resize: { [callbackRouter] viewport in
        Task {
          await callbackRouter.handleResize(viewport)
        }
      }
    )

    viewState.configuration = TerminalSurfaceOptions(
      backend: .inMemory(terminalSession),
      fontSize: style.fontSize,
      context: .window
    )
  }

  func attach(session: any HostedSceneSessionHandling) {
    self.session = session
    syncSessionStyle()
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
    syncSessionStyle()
  }

  func updateAppearance(_ colorScheme: SwiftUI.ColorScheme) {
    currentColorScheme = colorScheme
    syncSessionStyle()
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

  private func syncSessionStyle() {
    guard let session else {
      return
    }

    session.updateStyle(style.renderStyle(for: currentColorScheme.terminalUIScheme))
  }
}

@MainActor
protocol HostedSceneSessionHandling: AnyObject {
  func start() async throws -> RunLoopExitReason
  func sendInput(_ bytes: [UInt8])
  func resize(to size: Size)
  func updateStyle(_ style: TerminalRenderStyle)
  func stop()
}

extension HostedSceneSession: HostedSceneSessionHandling {}

extension SwiftUI.ColorScheme {
  fileprivate var terminalUIScheme: TerminalUI.ColorScheme {
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
