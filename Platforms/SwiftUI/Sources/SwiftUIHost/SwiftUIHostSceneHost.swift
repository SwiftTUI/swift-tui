public import Observation
import SwiftTUIRuntime
import SwiftUI

@MainActor
@Observable
public final class SwiftUIHostSceneHost {
  public let descriptor: SwiftUIHostSceneDescriptor

  public private(set) var isRunning = false
  public private(set) var lastError: String?
  public private(set) var focusPresentation: FocusPresentation = .none
  public private(set) var manualKeyboardPresentationRequested = false
  public private(set) var latestSurface: RasterSurface?
  public private(set) var latestSemanticSnapshot: SemanticSnapshot?
  public private(set) var focusedAccessibilityIdentity: Identity?
  public private(set) var style: SwiftUIHostTerminalStyle
  private(set) var latestPresentationDamage: PresentationDamage?

  @ObservationIgnored
  private let bridge: NativeSceneBridge

  @ObservationIgnored
  private var startTask: Task<Void, Never>?

  @ObservationIgnored
  private var accessibilityAnnouncer = HostedAccessibilityAnnouncer()

  @ObservationIgnored
  private var latestSemanticHostFrameSequence: UInt64?

  public init<A: SwiftTUIRuntime.App>(
    app: A,
    descriptor: SwiftUIHostSceneDescriptor,
    style: SwiftUIHostTerminalStyle,
    clipboardWriter: (@MainActor @Sendable (String) -> Bool)? = nil
  ) throws {
    self.descriptor = descriptor
    self.style = style
    let initialRenderStyle = style.renderStyle
    bridge = NativeSceneBridge(
      descriptor: descriptor,
      style: style
    )

    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 80, height: 24),
      appearance: initialRenderStyle.appearance,
      theme: initialRenderStyle.theme,
      onFrame: { [weak self] frame in
        self?.receiveFrame(frame)
      },
      onClipboardWrite: clipboardWriter ?? NativeClipboard.write
    )
    let session = try HostedSceneSession(
      for: app,
      sceneID: descriptor.id,
      surface: surface,
      runtimeIssueSink: SwiftUIRuntimeIssueLogger.sink,
      onFocusPresentationChange: { [weak self] presentation in
        self?.updateFocusPresentation(presentation)
      }
    )
    bridge.attach(session: session, surface: surface)
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
    focusedAccessibilityIdentity = nil
    latestPresentationDamage = nil
    latestSemanticHostFrameSequence = nil
    accessibilityAnnouncer.reset()
    manualKeyboardPresentationRequested = false
    bridge.updateKeyboardPresentation(
      focusPresentation: focusPresentation,
      manualKeyboardPresentationRequested: manualKeyboardPresentationRequested
    )
    isRunning = false
  }

  public func apply(style: SwiftUIHostTerminalStyle) {
    self.style = style
    bridge.apply(style: style)
  }

  public func resize(
    to size: CellSize,
    cellPixelSize: PixelSize?
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

  func receiveFrameForTesting(
    _ frame: SemanticHostFrame
  ) {
    receiveFrame(frame)
  }

  private func receiveFrame(
    _ frame: SemanticHostFrame
  ) {
    if let latestSemanticHostFrameSequence, frame.sequence <= latestSemanticHostFrameSequence {
      return
    }
    latestSemanticHostFrameSequence = frame.sequence
    latestSurface = frame.raster
    latestSemanticSnapshot = frame.semantics
    focusedAccessibilityIdentity = frame.focusedIdentity
    latestPresentationDamage = frame.rasterDamage
    NativeAccessibilityAnnouncementPoster.post(
      accessibilityAnnouncer.announcements(for: frame.semantics)
    )
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
