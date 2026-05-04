import SwiftTUI

@MainActor
final class NativeSceneBridge {
  enum BridgeError: Error, Equatable {
    case missingSession
  }

  let descriptor: SwiftUIHostSceneDescriptor

  private var style: SwiftUIHostTerminalStyle
  private var session: (any HostedSceneSessionHandling)?
  private var focusPresentation: FocusPresentation = .none
  private var manualKeyboardPresentationRequested = false
  private(set) var lastViewportSize: CellSize?
  private(set) var lastCellPixelSize: PixelSize?
  private(set) var lastPointerInputCapabilities: PointerInputCapabilities = .cellOnly

  init(
    descriptor: SwiftUIHostSceneDescriptor,
    style: SwiftUIHostTerminalStyle
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

  func apply(style: SwiftUIHostTerminalStyle) {
    self.style = style
    syncSessionStyle()
  }

  func resize(
    to size: CellSize,
    cellPixelSize: PixelSize?
  ) {
    guard size.width > 0, size.height > 0 else {
      return
    }

    let pointerInputCapabilities = Self.pointerInputCapabilities(
      for: cellPixelSize
    )
    guard
      size != lastViewportSize || cellPixelSize != lastCellPixelSize
        || pointerInputCapabilities != lastPointerInputCapabilities
    else {
      return
    }

    lastViewportSize = size
    lastCellPixelSize = cellPixelSize
    lastPointerInputCapabilities = pointerInputCapabilities
    session?.resize(
      to: size,
      cellPixelSize: cellPixelSize,
      pointerInputCapabilities: pointerInputCapabilities
    )
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

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?
  ) -> PointerInputCapabilities {
    guard let cellPixelSize else {
      return .cellOnly
    }
    return PointerInputCapabilities(
      precision: .subCell(
        source: .nativePixels,
        metrics: CellPixelMetrics(
          width: cellPixelSize.width,
          height: cellPixelSize.height,
          source: .reported
        )
      ),
      supportsHover: true
    )
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
  func resize(
    to size: CellSize,
    cellPixelSize: PixelSize?,
    pointerInputCapabilities: PointerInputCapabilities
  )
  func updateStyle(_ style: TerminalRenderStyle)
  func stop()
}

extension HostedSceneSession: HostedSceneSessionHandling {}
