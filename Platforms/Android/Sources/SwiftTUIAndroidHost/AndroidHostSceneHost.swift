@_spi(Runners) public import SwiftTUIRuntime
import Synchronization

#if os(Android)
  @_spi(MainActorUtilities) import _Concurrency
#endif

private struct AndroidHostSceneHostState: Sendable {
  var latestFrame: SemanticHostFrame?
  var encodingStyle: AndroidHostStyle?
  // Encode-at-copy scratch: the bytes of the last frame a consumer actually
  // copied, keyed by that frame's sequence. Frames the host never polls are
  // never encoded, and a future delta baseline tracks consumed frames by
  // construction (convergence proposal 2026-07-22-002, Stage C0).
  var encodedFrameBytes: [UInt8]?
  var encodedFrameSequence: UInt64?
  var encodedFrameCount = 0
  var latestEncodingErrorDescription: String?
  // Converged web-surface emission (convergence proposal 2026-07-22-002
  // Stage C1): non-nil once the Kotlin host's declaration selected the
  // web-surface wire. The encoding state carries the transmit-once image
  // set and, when delta was declared, the persistent style table and
  // baseline.
  var wireCapabilities = HostWireCapabilities()
  var webEncodingState: HostWireEncodingState?
  // Damage accumulated across committed-but-unconsumed frames: the poll
  // model skips frames, so a consumed frame's own damage (relative to the
  // previous COMMIT) under-covers the diff against the previous CONSUMED
  // frame. `nil` while valid means full repaint. Reset per consumed encode.
  var pendingDamage: PresentationDamage?
  var hasPendingDamage = false
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
    state.withLock(\.encodedFrameBytes)
  }

  var encodedFrameCount: Int {
    state.withLock(\.encodedFrameCount)
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
      state.encodingStyle = style
      // Encoding is deferred to the copy path (encode-at-copy): the poll
      // model deliberately skips intermediate frames, so encoding here
      // would pay full serialization for frames no consumer ever sees.
      // Damage accumulates so a later consumed frame's diff covers every
      // skipped commit; any frame without damage means full repaint.
      if state.hasPendingDamage {
        state.pendingDamage = Self.unionDamage(state.pendingDamage, frame.rasterDamage)
      } else {
        state.pendingDamage = frame.rasterDamage
        state.hasPendingDamage = true
      }
    }
  }

  func declareWireCapabilities(
    _ capabilities: HostWireCapabilities
  ) {
    state.withLock { state in
      state.wireCapabilities = capabilities
      state.webEncodingState =
        capabilities.maxWebSurfaceVersion >= 2
        ? HostWireEncodingState(
          deltaEnabled: capabilities.acceptsDeltaFrames
            && capabilities.maxWebSurfaceVersion >= 3
        )
        : nil
    }
  }

  private static func unionDamage(
    _ accumulated: PresentationDamage?,
    _ next: PresentationDamage?
  ) -> PresentationDamage? {
    guard let accumulated, let next else {
      // Either side demanding a full repaint keeps the union at full.
      return nil
    }
    return PresentationDamage(
      textRows: accumulated.textRows + next.textRows,
      requiresFullTextRepaint: accumulated.requiresFullTextRepaint
        || next.requiresFullTextRepaint,
      requiresFullGraphicsReplay: accumulated.requiresFullGraphicsReplay
        || next.requiresFullGraphicsReplay
    )
  }

  /// Serves the latest frame's encoded bytes, encoding at most once per
  /// consumed frame: the two-phase ABI copy (size query, then copy) and
  /// repeated polls of an unchanged frame all reuse the scratch.
  func copyEncodedFrameBytes(
    to outBuffer: UnsafeMutablePointer<UInt8>?,
    capacity: Int
  ) -> Int {
    state.withLock { state in
      guard let frame = state.latestFrame else {
        return 0
      }
      if state.encodedFrameSequence != frame.sequence || state.encodedFrameBytes == nil {
        let style = state.encodingStyle ?? .default
        if var webEncodingState = state.webEncodingState {
          // Converged web-surface emission: the accumulated damage makes the
          // record's diff consumption-relative, which is what keeps delta
          // records sound under the skipping poll (Stage C3).
          let model = HostWireFrameModel(
            surface: frame.raster,
            sequence: frame.sequence,
            semanticSnapshot: frame.semantics,
            focusedIdentity: frame.focusedIdentity,
            damage: state.hasPendingDamage ? state.pendingDamage : frame.rasterDamage,
            preferredLayoutSize: frame.preferredLayoutSize,
            terminalStyle: style.renderStyle
          )
          let output = WebSurfaceFrameEncoder.encode(
            model,
            fallbackBackground: style.renderStyle.appearance.backgroundColor,
            state: &webEncodingState
          )
          state.webEncodingState = webEncodingState
          state.encodedFrameBytes = Array(output.utf8)
          state.encodedFrameSequence = frame.sequence
          state.encodedFrameCount += 1
          state.latestEncodingErrorDescription = nil
        } else {
          do {
            state.encodedFrameBytes = try AndroidHostFrameEncoder.encode(frame, style: style)
            state.encodedFrameSequence = frame.sequence
            state.encodedFrameCount += 1
            state.latestEncodingErrorDescription = nil
          } catch {
            state.encodedFrameBytes = nil
            state.encodedFrameSequence = nil
            state.latestEncodingErrorDescription = String(describing: error)
            return 0
          }
        }
        state.pendingDamage = nil
        state.hasPendingDamage = false
      }
      guard let bytes = state.encodedFrameBytes else {
        return 0
      }
      guard let outBuffer = unsafe outBuffer, capacity >= bytes.count else {
        return bytes.count
      }
      unsafe outBuffer.update(from: bytes, count: bytes.count)
      return bytes.count
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
  @MainActor private var hasStartedScene = false
  /// The Kotlin host's declared wire capabilities (``declareCapabilities``;
  /// absence keeps the defaults — today's bytes). A declared
  /// `maxWebSurfaceVersion >= 2` selects the converged web-surface wire for
  /// frame serialization; `>= 3` with delta acceptance enables delta
  /// records.
  @MainActor package private(set) var wireCapabilities = HostWireCapabilities()

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

  /// The bytes of the last frame a consumer copied across the ABI. `nil`
  /// until the host first consumes a frame — encoding happens at copy time
  /// (encode-at-copy), so frames the poll skips are never serialized.
  public var latestFrameBytes: [UInt8]? {
    state.latestFrameBytes
  }

  /// How many distinct frames have been encoded for consumption — the
  /// encode-at-copy test seam: committed-but-never-copied frames must not
  /// advance it.
  package var consumedFrameEncodeCount: Int {
    state.encodedFrameCount
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

  /// Declares the host's wire capabilities from a `caps`-shaped JSON object
  /// (see `HostWireSchema.capabilityMappings` for the key set). Accepted
  /// only before the scene starts — capability-gated emission must never
  /// change shape mid-session. Returns whether the declaration was
  /// accepted; a rejected or malformed declaration keeps the defaults,
  /// which reproduce today's wire bytes exactly.
  @MainActor
  @discardableResult
  public func declareCapabilities(
    json: String
  ) -> Bool {
    guard !hasStartedScene,
      let capabilities = HostWireCapabilities.fromDeclarationJSON(json)
    else {
      return false
    }
    wireCapabilities = capabilities
    state.declareWireCapabilities(capabilities)
    return true
  }

  @MainActor
  public func start() {
    guard runTask == nil else {
      return
    }
    hasStartedScene = true

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

  /// Drives the Swift main-actor executor for one host frame, resuming any
  /// `@MainActor` continuations that became ready since the last tick (the run
  /// loop's own `await`, autonomous `.task` bodies, animation deadline wakes).
  /// The Android host has no OS run loop to drain the main-actor queue, so the
  /// render poll loop calls this each frame. See ``AndroidMainExecutorPump``.
  /// Returns a diagnostic status code (mirrored into the JNI bridge log).
  @MainActor
  @discardableResult
  public func tick() -> Int32 {
    #if os(Android)
      return AndroidMainExecutorPump.drainReadyJobs()
    #else
      return 0
    #endif
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
    unsafe state.copyEncodedFrameBytes(to: outBuffer, capacity: capacity)
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
