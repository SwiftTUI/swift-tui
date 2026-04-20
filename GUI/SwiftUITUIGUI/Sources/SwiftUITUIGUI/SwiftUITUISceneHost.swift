import Ghostty
import Observation
import SwiftUI
import TerminalUI

@MainActor
@Observable
public final class SwiftUITUISceneHost {
  public let descriptor: SwiftUITUISceneDescriptor

  public private(set) var isRunning = false
  public private(set) var lastError: String?
  public private(set) var focusPresentation: FocusPresentation = .none
  public private(set) var manualKeyboardPresentationRequested = false

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
    let initialRenderStyle = style.renderStyle
    bridge = GhosttySceneBridge(
      descriptor: descriptor,
      style: style
    )

    let session = try HostedSceneSession(
      for: app,
      sceneID: descriptor.id,
      initialSize: .init(width: 80, height: 24),
      appearance: initialRenderStyle.appearance,
      theme: initialRenderStyle.theme,
      onOutput: { [weak bridge] output in
        Task { @MainActor [weak bridge] in
          bridge?.receiveOutput(output)
        }
      },
      onFocusPresentationChange: { [weak self] presentation in
        self?.updateFocusPresentation(presentation)
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
    focusPresentation = .none
    manualKeyboardPresentationRequested = false
    bridge.updateKeyboardPresentation(
      focusPresentation: focusPresentation,
      manualKeyboardPresentationRequested: manualKeyboardPresentationRequested
    )
    isRunning = false
  }

  public func apply(style: SwiftUITUITerminalStyle) {
    bridge.apply(style: style)
  }

  public func toggleManualKeyboardPresentation() {
    guard focusPresentation.prefersTextInput == false else {
      return
    }

    manualKeyboardPresentationRequested.toggle()
    bridge.updateKeyboardPresentation(
      focusPresentation: focusPresentation,
      manualKeyboardPresentationRequested: manualKeyboardPresentationRequested
    )
  }

  var bridgeForTesting: GhosttySceneBridge {
    bridge
  }

  private func updateFocusPresentation(
    _ presentation: FocusPresentation
  ) {
    focusPresentation = presentation
    if presentation.prefersTextInput || presentation.semantics == .none {
      manualKeyboardPresentationRequested = false
    }
    bridge.updateKeyboardPresentation(
      focusPresentation: presentation,
      manualKeyboardPresentationRequested: manualKeyboardPresentationRequested
    )
  }
}
