import TerminalUI

@MainActor
final class NativeSceneBridge {
  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftUITUISceneDescriptor

  private var style: SwiftUITUITerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private var focusPresentation: FocusPresentation = .none
  private var manualKeyboardPresentationRequested = false
  private(set) var lastViewportSize: Size?
  private(set) var lastCellPixelSize: Size?

  init(
    descriptor: SwiftUITUISceneDescriptor,
    style: SwiftUITUITerminalStyle
  ) {
    self.descriptor = descriptor
    self.style = style
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

  func apply(style: SwiftUITUITerminalStyle) {
    self.style = style
    syncSessionStyle()
  }

  func resize(
    to size: Size,
    cellPixelSize: Size?
  ) {
    guard size.width > 0, size.height > 0 else {
      return
    }

    guard size != lastViewportSize || cellPixelSize != lastCellPixelSize else {
      return
    }

    lastViewportSize = size
    lastCellPixelSize = cellPixelSize
    session?.resize(to: size, cellPixelSize: cellPixelSize)
  }

  func send(
    _ event: InputEvent
  ) {
    session?.send(event)
  }

  func updateKeyboardPresentation(
    focusPresentation: FocusPresentation,
    manualKeyboardPresentationRequested: Bool
  ) {
    self.focusPresentation = focusPresentation
    self.manualKeyboardPresentationRequested = manualKeyboardPresentationRequested
  }

  private func syncSessionStyle() {
    session?.updateStyle(style.renderStyle)
  }

  private var allowsExpandedKeyboardPresentation: Bool {
    focusPresentation.prefersTextInput || manualKeyboardPresentationRequested
  }

  var focusPresentationForTesting: FocusPresentation {
    focusPresentation
  }

  var allowsExpandedKeyboardPresentationForTesting: Bool {
    allowsExpandedKeyboardPresentation
  }
}

@MainActor
protocol HostedSceneSessionHandling: AnyObject {
  func start() async throws -> RunLoopExitReason
  func send(_ event: InputEvent)
  func resize(to size: Size, cellPixelSize: Size?)
  func updateStyle(_ style: TerminalRenderStyle)
  func stop()
}

extension HostedSceneSession: HostedSceneSessionHandling {}
