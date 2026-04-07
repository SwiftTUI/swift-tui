import Foundation
import GhosttyTerminal
import SwiftUI
import TerminalUI

@MainActor
final class GhosttySceneBridge {
  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftUITUISceneDescriptor
  let viewState: TerminalViewState

  private var style: SwiftUITUITerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private var terminalSession: InMemoryTerminalSession! = nil
  private var bufferedOutput: [String] = []
  private var surfaceReady = false
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
    let terminalSession = InMemoryTerminalSession(
      write: { [weak self] data in
        Task { @MainActor [weak self] in
          self?.receiveTerminalInput(Array(data))
        }
      },
      resize: { [weak self] viewport in
        Task { @MainActor [weak self] in
          self?.handleSurfaceResize(viewport)
        }
      }
    )
    self.terminalSession = terminalSession

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

    session.updateStyle(style.renderStyle)
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
