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
  public private(set) var latestSurface: RasterSurface?
  public private(set) var style: SwiftUITUITerminalStyle

  @ObservationIgnored
  private let bridge: NativeSceneBridge

  @ObservationIgnored
  private var startTask: Task<Void, Never>?

  public init<A: TerminalUI.App>(
    app: A,
    descriptor: SwiftUITUISceneDescriptor,
    style: SwiftUITUITerminalStyle
  ) throws {
    self.descriptor = descriptor
    self.style = style
    let initialRenderStyle = style.renderStyle
    bridge = NativeSceneBridge(
      descriptor: descriptor,
      style: style
    )

    let session = try HostedSceneSession(
      for: app,
      sceneID: descriptor.id,
      initialSize: .init(width: 80, height: 24),
      appearance: initialRenderStyle.appearance,
      theme: initialRenderStyle.theme,
      onSurface: { [weak self] surface in
        self?.receiveSurface(surface)
      },
      onFocusPresentationChange: { [weak self] presentation in
        self?.updateFocusPresentation(presentation)
      }
    )
    bridge.attach(session: session)
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
    self.style = style
    bridge.apply(style: style)
  }

  public func resize(
    to size: Size,
    cellPixelSize: Size?
  ) {
    bridge.resize(to: size, cellPixelSize: cellPixelSize)
  }

  public func send(
    _ event: InputEvent
  ) {
    bridge.send(event)
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

  var bridgeForTesting: NativeSceneBridge {
    bridge
  }

  private func receiveSurface(
    _ surface: RasterSurface
  ) {
    latestSurface = surface
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
