@_spi(Runners) public import SwiftTUIRuntime
import Synchronization

#if os(Android)
  @_spi(MainActorUtilities) import _Concurrency
#endif

private struct AndroidHostSceneHostState: Sendable {
  var latestFrame: SemanticHostFrame?
  var latestFrameBytes: [UInt8]?
  var latestEncodingErrorDescription: String?
  var focusPresentation: FocusPresentation = .none
  var surfaceSize: CellSize
  var cellPixelSize: PixelSize?
  var lastErrorDescription: String?
  // Latest clipboard-write requested by the running app (an `onClipboardWrite`
  // from the runtime). Drained exactly once when the client copies it across
  // the ABI, so a system clipboard write happens per copy rather than per poll.
  var pendingClipboardText: String?
}

private final class AndroidHostSceneHostStateBox: Sendable {
  private let state: Mutex<AndroidHostSceneHostState>

  init(
    _ state: AndroidHostSceneHostState
  ) {
    self.state = Mutex(state)
  }

  var latestFrame: SemanticHostFrame? {
    state.withLock(\.latestFrame)
  }

  var latestFrameBytes: [UInt8]? {
    state.withLock(\.latestFrameBytes)
  }

  var latestEncodingErrorDescription: String? {
    state.withLock(\.latestEncodingErrorDescription)
  }

  var focusPresentation: FocusPresentation {
    state.withLock(\.focusPresentation)
  }

  var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  var cellPixelSize: PixelSize? {
    state.withLock(\.cellPixelSize)
  }

  var lastErrorDescription: String? {
    state.withLock(\.lastErrorDescription)
  }

  func updateFrame(
    _ frame: SemanticHostFrame,
    style: AndroidHostStyle
  ) {
    state.withLock { state in
      state.latestFrame = frame
      do {
        state.latestFrameBytes = try AndroidHostFrameEncoder.encode(frame, style: style)
        state.latestEncodingErrorDescription = nil
      } catch {
        state.latestFrameBytes = nil
        state.latestEncodingErrorDescription = String(describing: error)
      }
    }
  }

  func updateFocusPresentation(
    _ presentation: FocusPresentation
  ) {
    state.withLock { state in
      state.focusPresentation = presentation
    }
  }

  func updateLastErrorDescription(
    _ description: String
  ) {
    state.withLock { state in
      state.lastErrorDescription = description
    }
  }

  func updateResize(
    surfaceSize: CellSize,
    cellPixelSize: PixelSize
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.cellPixelSize = cellPixelSize
    }
  }

  func recordClipboardWrite(
    _ text: String
  ) {
    // An empty write carries nothing to deliver; ignore it so a size query can
    // never report a 0-byte payload that looks like "nothing pending".
    guard !text.isEmpty else {
      return
    }
    state.withLock { state in
      state.pendingClipboardText = text
    }
  }

  /// Copies the pending clipboard text as UTF-8 into `outBuffer`, draining it on
  /// a successful copy. Mirrors `copyLatestFrameBytes`: a `nil` buffer or an
  /// undersized `capacity` is a size query that reports the byte count without
  /// draining, so the two-call (size-then-copy) ABI handshake delivers a copy
  /// exactly once.
  func copyPendingClipboardBytes(
    to outBuffer: UnsafeMutablePointer<UInt8>?,
    capacity: Int
  ) -> Int {
    state.withLock { state in
      guard let text = state.pendingClipboardText else {
        return 0
      }
      let bytes = Array(text.utf8)
      guard let outBuffer = unsafe outBuffer, capacity >= bytes.count else {
        return bytes.count
      }
      unsafe outBuffer.update(from: bytes, count: bytes.count)
      state.pendingClipboardText = nil
      return bytes.count
    }
  }
}

public final class AndroidHostSceneHost {
  public let manifest: SceneManifest
  public let descriptor: SceneDescriptor
  public let surface: HostedRasterSurface
  @MainActor public let session: HostedSceneSession

  private let state: AndroidHostSceneHostStateBox

  @MainActor private var runTask: Task<Void, Never>?

  @MainActor
  public convenience init<A: App>(
    app: A,
    sceneID: WindowIdentifier? = nil,
    style: AndroidHostStyle = .default
  ) throws {
    let manifest = SceneManifest(for: app)
    let selectedSceneID = sceneID ?? manifest.defaultSceneID
    guard let descriptor = manifest.scenes.first(where: { $0.id == selectedSceneID }) else {
      throw HostedSceneSessionError.sceneNotFound(selectedSceneID)
    }

    let state = AndroidHostSceneHostStateBox(
      AndroidHostSceneHostState(
        surfaceSize: style.initialSurfaceSize,
        cellPixelSize: nil
      )
    )
    let surface = HostedRasterSurface(
      surfaceSize: style.initialSurfaceSize,
      appearance: style.renderStyle.appearance,
      theme: style.renderStyle.theme,
      frameDelivery: .assumedMainActor,
      onFrame: { frame in
        state.updateFrame(frame, style: style)
      },
      onClipboardWrite: { text in
        state.recordClipboardWrite(text)
        return true
      }
    )
    let session = try HostedSceneSession(
      for: app,
      sceneID: selectedSceneID,
      surface: surface,
      renderMode: .sync,
      onFocusPresentationChange: { presentation in
        state.updateFocusPresentation(presentation)
      }
    )

    self.init(
      manifest: manifest,
      descriptor: descriptor,
      surface: surface,
      session: session,
      state: state
    )
  }

  @MainActor
  private init(
    manifest: SceneManifest,
    descriptor: SceneDescriptor,
    surface: HostedRasterSurface,
    session: HostedSceneSession,
    state: AndroidHostSceneHostStateBox
  ) {
    self.manifest = manifest
    self.descriptor = descriptor
    self.surface = surface
    self.session = session
    self.state = state
  }

  public var latestFrame: SemanticHostFrame? {
    state.latestFrame
  }

  public var latestFrameBytes: [UInt8]? {
    state.latestFrameBytes
  }

  public var latestEncodingErrorDescription: String? {
    state.latestEncodingErrorDescription
  }

  public var focusPresentation: FocusPresentation {
    state.focusPresentation
  }

  public var surfaceSize: CellSize {
    state.surfaceSize
  }

  public var cellPixelSize: PixelSize? {
    state.cellPixelSize
  }

  public var lastErrorDescription: String? {
    state.lastErrorDescription
  }

  @MainActor
  public func start() {
    guard runTask == nil else {
      return
    }

    #if os(Android)
      runTask = Task.immediate { @MainActor [weak self] in
        guard let self else {
          return
        }
        defer {
          runTask = nil
        }
        do {
          _ = try await session.start()
        } catch {
          state.updateLastErrorDescription(String(describing: error))
        }
      }
    #else
      runTask = Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        defer {
          runTask = nil
        }
        do {
          _ = try await session.start()
        } catch {
          state.updateLastErrorDescription(String(describing: error))
        }
      }
    #endif
  }

  @MainActor
  public func stop() {
    session.stop()
  }

  @MainActor
  public func resize(
    columns: Int,
    rows: Int,
    cellPixelWidth: Double,
    cellPixelHeight: Double
  ) {
    let size = CellSize(
      width: max(1, columns),
      height: max(1, rows)
    )
    let cellPixelSize = PixelSize(
      width: max(1, Int(cellPixelWidth.rounded())),
      height: max(1, Int(cellPixelHeight.rounded()))
    )
    let metrics = CellPixelMetrics(
      width: cellPixelSize.width,
      height: cellPixelSize.height,
      source: .reported
    )

    state.updateResize(surfaceSize: size, cellPixelSize: cellPixelSize)
    surface.updateSurfaceSize(size)
    surface.updateSurfaceCapabilities(
      cellPixelSize: cellPixelSize,
      pointerInputCapabilities: PointerInputCapabilities(
        precision: .subCell(source: .nativePixels, metrics: metrics),
        supportsHover: true,
        supportsPreciseScroll: true
      )
    )
    session.requestSurfaceRefresh()
  }

  @MainActor
  public func sendInput(
    _ bytes: [UInt8]
  ) {
    session.sendInput(bytes)
  }

  public func copyLatestFrameBytes(
    to outBuffer: UnsafeMutablePointer<UInt8>?,
    capacity: Int
  ) -> Int {
    guard let bytes = latestFrameBytes else {
      return 0
    }
    guard let outBuffer = unsafe outBuffer, capacity >= bytes.count else {
      return bytes.count
    }
    unsafe outBuffer.update(from: bytes, count: bytes.count)
    return bytes.count
  }

  /// Drains the latest app-requested clipboard text as UTF-8 bytes. The client
  /// polls this across the ABI and forwards the bytes to the system clipboard.
  public func copyPendingClipboardText(
    to outBuffer: UnsafeMutablePointer<UInt8>?,
    capacity: Int
  ) -> Int {
    unsafe state.copyPendingClipboardBytes(to: outBuffer, capacity: capacity)
  }

}

extension AndroidHostSceneHost: Sendable {}
