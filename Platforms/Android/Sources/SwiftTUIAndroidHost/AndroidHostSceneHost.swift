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
  var encodedUpToSequence: UInt64?
  var encodedFrameCount = 0
  // Delivery-coupled ratchet (plan 2026-07-28-006, S3a): the scratch above is
  // encoded against a *candidate* encoding state that becomes committed only
  // when the copy leg actually writes bytes out. A size query, an abandoned
  // handshake, or an undersized copy therefore never advances the wire's
  // cross-frame state, so the bytes a consumer receives always name a
  // baseline the encoder still believes in.
  var candidateEncodingState: HostWireEncodingState?
  // The accumulated damage the candidate encode consumed. Held aside rather
  // than dropped so an abandoned handshake can fold it back into the live
  // accumulator; dropped for good only at commit.
  var candidateDamage: PresentationDamage?
  var hasCandidateDamage = false
  var latestEncodingErrorDescription: String?
  // Converged web-surface emission (convergence proposal 2026-07-22-002;
  // the legacy keyed-JSON wire retired in Stage C4): the encoding state
  // carries the transmit-once image set and, once the declaration enabled
  // delta, the persistent style table and baseline.
  var wireCapabilities = HostWireCapabilities()
  var webEncodingState = HostWireCapabilities().negotiatedEncodingState()
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
      // The declaration negotiates the record shape: delta acceptance flips
      // steady frames to delta records. Undeclared hosts keep receiving full
      // web-surface frames.
      //
      // Ingress lifecycle: accepted only before scene start (see
      // `declareCapabilities(json:)`), so this re-anchor always lands before
      // any frame has been emitted.
      state.webEncodingState = capabilities.negotiatedEncodingState()
      Self.invalidateEncodeScratch(&state)
    }
  }

  /// Re-anchors the encoding state on a caller-chosen epoch.
  ///
  /// Test-only seam, and deliberately not part of the host's public or
  /// `package` surface: the byte-frozen host-wire conformance fixtures name an
  /// exact `epoch`, which a process-global epoch counter cannot reproduce. It
  /// still routes through the declaration's negotiated door, because that door
  /// — not a transport — owns what an epoch is.
  func pinWireEncodingEpoch(
    _ epochID: UInt32
  ) {
    state.withLock { state in
      state.webEncodingState = state.wireCapabilities.negotiatedEncodingState(
        epochID: epochID)
      Self.invalidateEncodeScratch(&state)
    }
  }

  func requestResync(
    _ request: HostWireResyncRequest
  ) {
    state.withLock { state in
      state.webEncodingState.requestResync(request)
      // The latest frame may already have encode-at-copy scratch, encoded
      // against a candidate that predates the repair. Dropping the whole
      // scratch forces the next size/copy handshake to re-encode that same
      // frame from the repaired committed state.
      Self.invalidateEncodeScratch(&state)
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
  ///
  /// Encode and delivery are two distinct legs here, which is what makes this
  /// transport — alone among the three — able to ratchet encoder state for
  /// bytes that never left the process. The split is therefore explicit:
  ///
  /// - **Encode leg.** A size query (`outBuffer == nil`) re-encodes whenever
  ///   the scratch does not already hold the latest frame, against a
  ///   *candidate* copy of the encoding state.
  /// - **Delivery leg.** A copy serves the scratch the preceding size query
  ///   measured — it never re-encodes a newer frame, because reporting one
  ///   frame's size and delivering another is the straddle this stage closes —
  ///   and promotes candidate → committed only once bytes are written out.
  func copyEncodedFrameBytes(
    to outBuffer: UnsafeMutablePointer<UInt8>?,
    capacity: Int
  ) -> Int {
    state.withLock { state in
      guard let frame = state.latestFrame else {
        return 0
      }
      let isDeliveryLeg = unsafe outBuffer != nil
      let scratchHoldsLatestFrame =
        state.encodedFrameBytes != nil && state.encodedUpToSequence == frame.sequence
      if !scratchHoldsLatestFrame, state.encodedFrameBytes == nil || !isDeliveryLeg {
        let style = state.encodingStyle ?? .default
        // The candidate carries every axis of cross-frame state: the
        // transmit-once image set, the accumulated style epoch, and the delta
        // baseline. Committed state is untouched until delivery succeeds.
        var candidate = state.webEncodingState
        // Converged web-surface emission (the only Android wire since the
        // Stage C4 retirement): the accumulated damage makes the record's
        // diff consumption-relative, which is what keeps delta records
        // sound under the skipping poll (Stage C3). An earlier abandoned
        // candidate's damage folds back in here so no committed frame's
        // damage is lost by a handshake that never delivered.
        let consumedDamage = Self.unionAccumulatedDamage(&state)
        let model = HostWireFrameModel(
          surface: frame.raster,
          sequence: frame.sequence,
          semanticSnapshot: frame.semantics,
          focusedIdentity: frame.focusedIdentity,
          damage: consumedDamage.hasDamage ? consumedDamage.damage : frame.rasterDamage,
          preferredLayoutSize: frame.preferredLayoutSize,
          terminalStyle: style.renderStyle
        )
        let output = WebSurfaceFrameEncoder.encode(
          model,
          fallbackBackground: style.renderStyle.appearance.backgroundColor,
          state: &candidate
        )
        state.encodedFrameBytes = Array(output.utf8)
        state.encodedUpToSequence = frame.sequence
        state.encodedFrameCount += 1
        state.latestEncodingErrorDescription = nil
        state.candidateEncodingState = candidate
        state.candidateDamage = consumedDamage.damage
        state.hasCandidateDamage = consumedDamage.hasDamage
        // Frames arriving during this handshake accumulate from empty, so a
        // commit drops exactly the damage the delivered record covered.
        state.pendingDamage = nil
        state.hasPendingDamage = false
      }
      guard let bytes = state.encodedFrameBytes else {
        return 0
      }
      guard let outBuffer = unsafe outBuffer, capacity >= bytes.count else {
        // A size query, or a copy whose buffer cannot hold the record: no
        // bytes left the process, so no state ratchets. The client retries
        // with the reported size.
        return bytes.count
      }
      unsafe outBuffer.update(from: bytes, count: bytes.count)
      if let candidate = state.candidateEncodingState {
        state.webEncodingState = candidate
        state.candidateEncodingState = nil
        state.candidateDamage = nil
        state.hasCandidateDamage = false
      }
      return bytes.count
    }
  }

  /// Folds an abandoned candidate's damage back into the live accumulator and
  /// returns the union the next encode must cover.
  private static func unionAccumulatedDamage(
    _ state: inout AndroidHostSceneHostState
  ) -> (damage: PresentationDamage?, hasDamage: Bool) {
    guard state.hasCandidateDamage else {
      return (state.pendingDamage, state.hasPendingDamage)
    }
    guard state.hasPendingDamage else {
      return (state.candidateDamage, true)
    }
    return (unionDamage(state.candidateDamage, state.pendingDamage), true)
  }

  /// Drops the encode-at-copy scratch and any uncommitted candidate, folding
  /// the candidate's damage back so the next encode still covers it.
  private static func invalidateEncodeScratch(
    _ state: inout AndroidHostSceneHostState
  ) {
    let restored = unionAccumulatedDamage(&state)
    state.pendingDamage = restored.damage
    state.hasPendingDamage = restored.hasDamage
    state.candidateDamage = nil
    state.hasCandidateDamage = false
    state.candidateEncodingState = nil
    state.encodedFrameBytes = nil
    state.encodedUpToSequence = nil
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
  /// The Kotlin host's declared wire capabilities from ``declareCapabilities``.
  /// An absent declaration keeps the defaults and today's bytes.
  /// Every Android host receives converged web-surface frames.
  /// The declaration's one bit selects full or delta records.
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

  /// How many frame records have been encoded for consumption — the
  /// encode-at-copy test seam: committed-but-never-copied frames must not
  /// advance it, while a requested same-sequence resync re-encode must.
  package var consumedFrameEncodeCount: Int {
    state.encodedFrameCount
  }

  /// Test-only deterministic epoch pin for the host-wire conformance oracle;
  /// see `AndroidHostSceneHostStateBox.pinWireEncodingEpoch(_:)`.
  func pinWireEncodingEpoch(
    _ epochID: UInt32
  ) {
    state.pinWireEncodingEpoch(epochID)
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
  /// change shape mid-session. Returns whether the declaration was accepted.
  /// A rejected or malformed declaration keeps the defaults,
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

  /// Requests delivery-state repair from a `resync`-shaped JSON object.
  ///
  /// Unlike capability declaration, resync is valid throughout the session:
  /// it changes neither record shape nor connection epoch.
  @discardableResult
  public func requestResync(
    json: String
  ) -> Bool {
    guard let request = HostWireResyncRequest.fromRequestJSON(json) else {
      return false
    }
    state.requestResync(request)
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
