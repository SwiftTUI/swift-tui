public import SwiftTUIRuntime

/// A scene on the framework's run loop, driven by a test one frame at a time.
///
/// The harness builds `content` on a real `RunLoop` and gives that run loop
/// a virtual frame clock. Nothing sleeps and nothing reads the wall clock.
/// The test moves time with ``advance(by:)`` and ``advanceToNextWake()``,
/// delivers input with ``press(_:)``, ``send(_:)``, ``paste(_:)`` and
/// ``resize(to:)``, and reads what the run loop presented from ``frame`` and
/// ``lines``. A frame at 400 ms of an 800 ms animation is the same frame on
/// every machine.
///
/// ```swift
/// let harness = try RunLoopTestHarness(size: CellSize(width: 40, height: 6)) {
///   Gauge()
/// }
/// defer { harness.shutdown() }
///
/// // The frame of the key press, which starts an animation in `Gauge`.
/// try harness.press(KeyPress(.character("g")))
/// let start = harness.now
/// // Then every frame of the animation, each at its own instant.
/// while try harness.advanceToNextWake() {
///   let elapsed = start.duration(to: harness.now)
///   #expect(harness.lines[0] == Gauge.text(at: elapsed))
/// }
/// ```
///
/// A loop like this one ends because the animation arms nothing after its
/// last frame. It does not end on a scene that has a view under
/// `.transition(_:)` on screen: the engine currently keeps a frame armed for
/// such a view for as long as it is present. Step that scene a known number
/// of times, or with ``advance(by:)``.
///
/// ## What runs
///
/// The run loop, the renderer, the frame scheduler, the focus tracker and
/// the registries are the ones an interactive session uses. Selective
/// evaluation is on after the first frame, as in a session. Every call
/// renders on the run loop's synchronous frame driver, inside the
/// registration scope that `RunLoop.run()` installs, so a `withAnimation`
/// in a button action or a key handler registers its animation and its
/// completion.
///
/// The presentation surface records what it is given. It has the size passed
/// to ``init(size:content:)``, reports a Unicode terminal with the fallback
/// appearance and cell-only pointer input, and has no clipboard. A link the
/// scene opens is declined: the open-link action reports `false` and no
/// program starts.
///
/// ## Virtual time
///
/// The clock starts at `MonotonicInstant.zero`, the instant of the first
/// frame, and moves only when the test moves it. A frame deadline is an
/// instant at which the scheduler has a frame armed: the next tick of an
/// animation, a gesture's timer, a scroll that is coming to rest. The input
/// calls render at the current instant and do not move the clock.
///
/// ## Limits
///
/// - The asynchronous render modes are not driven. Every frame is rendered
///   by the synchronous driver.
/// - A `.task` starts when its view appears, and its body runs when the test
///   suspends. The harness neither runs task work nor waits for it. What a
///   task changed is rendered by the next call.
/// - A view that reads the wall clock itself, such as `TimelineView`, does
///   not follow the virtual clock.
/// - A `withAnimation` completion registered in the test body, outside a
///   call of the harness, is never called: no run loop is in scope there to
///   register it with. Start such an animation from the scene.
/// - The harness is not a session that can end. The framework's exit keys
///   are off, so `Ctrl+C` reaches the scene as any other key, and the
///   `requestTermination` action reports `false`.
///
/// ## Errors
///
/// A call that renders throws what the run loop throws. It also throws when
/// the harness has been shut down, when it is made from a callback that runs
/// during another call of the same harness, and when the scene still has a
/// frame due after 16 render passes at one instant, which is what a view
/// that changes its own state on every frame causes.
@MainActor
@_spi(Testing) public final class RunLoopTestHarness<Content: View> {
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private let scheduler: FrameScheduler
  private let surface: RunLoopTestHarnessSurface
  private let clock: RunLoopTestHarnessClock
  private let announcements: RunLoopTestHarnessAnnouncementRelay
  private let rootIdentity: Identity
  /// The run loop's count of the frames it committed. The frame ordinals in
  /// its diagnostics continue from it.
  private var renderedFrames = 0
  private var isDriving = false
  private var isShutDown = false

  /// Builds `content` on a run loop and renders the first frame.
  ///
  /// The run loop presents to a recording surface of `size` cells. The frame
  /// clock is virtual from the start and stands at the instant of the first
  /// frame, `MonotonicInstant.zero`. After the first frame the harness turns
  /// selective evaluation on, as the run loop of a session does, and renders
  /// whatever the first frame left due at that instant, so ``frameCount``
  /// can be more than 1 when the initializer returns.
  ///
  /// - Parameters:
  ///   - size: The size of the surface, in cells. Both dimensions are
  ///     positive.
  ///   - content: The root view. The run loop calls it for every frame.
  /// - Throws: An error when `size` has a dimension that is not positive,
  ///   and whatever rendering the first frame throws.
  @_spi(Testing) public init(size: CellSize, @ViewBuilder content: @escaping () -> Content) throws {
    guard size.width > 0, size.height > 0 else {
      throw RunLoopTestHarnessError.emptySurface(size)
    }
    let rootIdentity = Identity(components: ["RunLoopTestHarness"])
    let surface = RunLoopTestHarnessSurface(surfaceSize: size)
    let clock = RunLoopTestHarnessClock()
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    // The harness is not a session that can end, so no key exits it.
    let runLoop = SwiftTUIRuntime.RunLoop<Int, Content>(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      inputReader: RunLoopTestHarnessInputReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      exitKeyBindings: .none,
      viewBuilder: { _, _ in content() }
    )
    // Virtual before the first frame: no frame of this run loop ever reads
    // the wall clock.
    runLoop.frameClock = { clock.now }
    // The focus wiring `run()` installs before its first frame.
    runLoop.installFocusTrackerInvalidator()
    self.runLoop = runLoop
    self.scheduler = scheduler
    self.surface = surface
    self.clock = clock
    announcements = RunLoopTestHarnessAnnouncementRelay(runLoop)
    self.rootIdentity = rootIdentity

    // The start of `run()`: the first frame under the initial-presentation
    // policy, then selective evaluation, then the frames that are still due.
    scheduler.requestInvalidation(of: [rootIdentity])
    try drive { try renderPass(.initialPresentation) }
    runLoop.renderer.enableSelectiveEvaluation()
    try drive { try renderDueFrames() }
    guard surface.presentedFrameCount > 0 else {
      throw RunLoopTestHarnessError.noFirstFrame
    }
  }

  // MARK: - What was presented

  /// The surface the run loop presented last.
  ///
  /// Its size is the size of the harness's surface. It keeps the cells, the
  /// style runs and the image attachments of the frame.
  @_spi(Testing) public var frame: RasterSurface {
    surface.presentedSurface ?? RasterSurface(size: surface.surfaceSize, lines: [])
  }

  /// The text of ``frame``, one string for each row, top row first.
  ///
  /// These are `frame.lines`: blank cells without a style at the end of a
  /// row are left out.
  @_spi(Testing) public var lines: [String] {
    frame.lines
  }

  /// The number of frames presented so far, the first one included.
  @_spi(Testing) public var frameCount: Int {
    surface.presentedFrameCount
  }

  // MARK: - Virtual time

  /// The instant of the virtual frame clock.
  ///
  /// It starts at `MonotonicInstant.zero`. Only ``advance(by:)`` and
  /// ``advanceToNextWake()`` move it.
  @_spi(Testing) public var now: MonotonicInstant {
    clock.now
  }

  /// The instant of the next frame the scheduler has armed, or `nil` when it
  /// has none.
  ///
  /// After a call that renders, this is the next frame deadline after
  /// ``now``: every frame that was due at ``now`` has been rendered. After a
  /// change made outside the run loop and before ``render()``, a frame is
  /// due and this is ``now`` itself. It is `nil` after ``shutdown()``.
  ///
  /// This is what the scheduler has armed, whatever armed it. The engine
  /// currently keeps a deadline armed for a view under `.transition(_:)` for
  /// as long as the view is present, so this is not `nil` while such a view
  /// is on screen.
  @_spi(Testing) public var nextWake: MonotonicInstant? {
    guard !isShutDown else {
      return nil
    }
    return scheduler.nextWakeInstant(after: clock.now)
  }

  /// Moves the clock forward by `duration` and renders every frame that
  /// falls due on the way.
  ///
  /// Frames already due at ``now`` are rendered first. Then each frame
  /// deadline inside the interval is rendered in order, at its own instant.
  /// A deadline exactly at the end of the interval is inside it. A frame can
  /// arm a deadline that is still inside the interval, and that one is
  /// rendered too. The clock is then left at the instant `duration` after
  /// where it started, whether or not a frame was rendered there.
  ///
  /// - Parameter duration: How far to move the clock. Not negative.
  /// - Returns: The number of frames presented.
  @discardableResult
  @_spi(Testing) public func advance(by duration: Duration) throws -> Int {
    guard duration >= .zero else {
      throw RunLoopTestHarnessError.negativeDuration(duration)
    }
    let presentedBefore = surface.presentedFrameCount
    try drive {
      let target = clock.now.advanced(by: duration)
      try renderDueFrames()
      while !isShutDown, let wake = scheduler.nextWakeInstant(after: clock.now), wake <= target {
        guard wake > clock.now else {
          throw RunLoopTestHarnessError.sceneDidNotSettle(clock.now)
        }
        clock.now = wake
        try renderDueFrames()
      }
      clock.now = target
    }
    return surface.presentedFrameCount - presentedBefore
  }

  /// Moves the clock to ``nextWake`` and renders the frame that is due there.
  ///
  /// When that frame makes another frame due at the same instant, that one
  /// is rendered too.
  ///
  /// - Returns: `false` when no frame is armed. The clock does not move and
  ///   nothing is rendered.
  @discardableResult
  @_spi(Testing) public func advanceToNextWake() throws -> Bool {
    try drive {
      guard let wake = scheduler.nextWakeInstant(after: clock.now) else {
        return false
      }
      if wake > clock.now {
        clock.now = wake
      }
      try renderDueFrames()
      return true
    }
  }

  // MARK: - Input

  /// Delivers a key press through the run loop's input dispatch and renders
  /// the frame it causes.
  ///
  /// The key goes where a key goes in a session: to key commands, to the
  /// focused view's handlers, then to focus traversal and activation. The
  /// clock does not move.
  @_spi(Testing) public func press(_ key: KeyPress) throws {
    try deliver(.input(.key(key)))
  }

  /// Delivers a mouse event through the run loop's input dispatch and
  /// renders the frame it causes.
  ///
  /// The event is delivered at the current virtual instant: its `timestamp`
  /// is replaced with ``now``, so a gesture's timer and a drag's velocity
  /// follow the virtual clock. An event that needs no frame, such as pointer
  /// motion over a view that does not track it, renders none. The clock does
  /// not move.
  @_spi(Testing) public func send(_ event: MouseEvent) throws {
    var stamped = event
    stamped.timestamp = clock.now
    try deliver(.input(.mouse(stamped)))
  }

  /// Delivers `text` as one bracketed paste through the run loop's input
  /// dispatch and renders the frame it causes.
  ///
  /// The paste goes where a paste goes in a session: to a drop destination
  /// when the text is a list of paths, else to the focused view. The clock
  /// does not move.
  @_spi(Testing) public func paste(_ text: String) throws {
    try deliver(.input(.paste(PasteEvent(content: text))))
  }

  /// Changes the size of the surface, delivers the window-change signal a
  /// terminal sends, and renders the frame it causes.
  ///
  /// The clock does not move.
  ///
  /// - Parameter size: The new size, in cells. Both dimensions are positive.
  @_spi(Testing) public func resize(to size: CellSize) throws {
    guard size.width > 0, size.height > 0 else {
      throw RunLoopTestHarnessError.emptySurface(size)
    }
    try drive {
      surface.surfaceSize = size
      _ = runLoop.handle(.signal(.windowChange))
      try renderDueFrames()
    }
  }

  // MARK: - After a change made outside the run loop

  /// Renders a frame now, for a change the test made outside the run loop.
  ///
  /// A change the view graph observes, such as a write through a `Binding`
  /// to `@State` or a change to an observable model a view reads, has
  /// already asked for a frame. That frame is rendered as the run loop
  /// renders it in a session. When no frame is due, the root is invalidated
  /// first: a frame is always presented, and it shows a change the view
  /// graph cannot observe. The clock does not move.
  @_spi(Testing) public func render() throws {
    try drive {
      if !scheduler.hasPendingFrame(at: clock.now) {
        scheduler.requestInvalidation(of: [rootIdentity])
      }
      try renderDueFrames()
    }
  }

  /// Ends the run loop's work: the tasks the scene started are cancelled and
  /// no frame is rendered after it.
  ///
  /// ``frame``, ``lines``, ``frameCount`` and ``now`` keep their values,
  /// ``nextWake`` is `nil`, and a call that renders throws. Calling this more
  /// than once does nothing more. A harness that is released without it
  /// releases the run loop, which cancels the scene's tasks too.
  @_spi(Testing) public func shutdown() {
    guard !isShutDown else {
      return
    }
    isShutDown = true
    runLoop.endManuallyDrivenSession()
  }

  // MARK: - Driving the run loop

  /// Runs `body` as the run loop's own task runs its work: inside the
  /// registration scope `RunLoop.run()` installs, so animations, transitions
  /// and completions registered by an action or a lifecycle handler reach
  /// this run loop's animation controller.
  ///
  /// One binding of that scope is replaced. The scope binds the run loop
  /// itself as the accessibility-announcement sink, and a `.task` that a
  /// frame starts copies the bindings of the scope it starts in, so every
  /// running task would hold the run loop. A session ends with `run()`,
  /// which cancels its tasks. A harness can be released without
  /// ``shutdown()``, and then the run loop must be free to go, because it is
  /// the run loop's release that cancels the tasks. The relay bound here
  /// forwards announcements to the run loop and does not hold it.
  private func drive<Result>(_ body: () throws -> Result) throws -> Result {
    guard !isShutDown else {
      throw RunLoopTestHarnessError.shutDown
    }
    guard !isDriving else {
      throw RunLoopTestHarnessError.reentrantCall
    }
    isDriving = true
    defer { isDriving = false }
    return try runLoop.withRuntimeRegistrationScope {
      try AccessibilityAnnouncementStorage.withSink(announcements) {
        try body()
      }
    }
  }

  private func deliver(_ event: RuntimeEvent) throws {
    try drive {
      // No event the harness sends ends a session: the exit keys are off.
      _ = runLoop.handle(event)
      try renderDueFrames()
    }
  }

  /// Renders every frame that is due at the current instant.
  ///
  /// One pass is one drain of the run loop's frame driver, which stops after
  /// `RunLoop.maxFramesPerDrainPass` frames. A session enters the next pass
  /// at once while a frame is due, and so does this.
  private func renderDueFrames() throws {
    var passes = 0
    while !isShutDown, scheduler.hasPendingFrame(at: clock.now) {
      guard passes < maximumRenderPassesAtOneInstant else {
        throw RunLoopTestHarnessError.sceneDidNotSettle(clock.now)
      }
      passes += 1
      try renderPass(.normal)
    }
  }

  private func renderPass(
    _ policy: SwiftTUIRuntime.RunLoop<Int, Content>.FrameDrainPolicy
  ) throws {
    // A copy, so a callback that reads the harness during the pass does not
    // overlap an exclusive access to the stored count.
    var frames = renderedFrames
    defer { renderedFrames = frames }
    try runLoop.renderPendingFrames(renderedFrames: &frames, drainPolicy: policy)
  }
}

/// How many drains of the frame driver a harness call makes at one instant
/// before it reports that the scene does not settle.
private let maximumRenderPassesAtOneInstant = 16

/// The frame clock of a harness: an instant the harness sets.
@MainActor
private final class RunLoopTestHarnessClock {
  var now = MonotonicInstant.zero
}

/// The accessibility-announcement sink a harness binds for its calls: it
/// passes each announcement on to the run loop, and holds the run loop
/// weakly. See `RunLoopTestHarness.drive(_:)`.
@MainActor
private final class RunLoopTestHarnessAnnouncementRelay: AccessibilityAnnouncementSink {
  private weak var sink: (any AccessibilityAnnouncementSink)?

  init(_ sink: any AccessibilityAnnouncementSink) {
    self.sink = sink
  }

  func announceAccessibility(_ announcement: AccessibilityAnnouncement) {
    sink?.announceAccessibility(announcement)
  }
}

/// The terminal-shaped presentation surface of a harness. It keeps the last
/// presented raster and counts the frames.
private final class RunLoopTestHarnessSurface: PresentationSurface {
  var surfaceSize: CellSize
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  private(set) var presentedSurface: RasterSurface?
  private(set) var presentedFrameCount = 0

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentedSurface = surface
    presentedFrameCount += 1
    return TerminalPresentationMetrics.fullRepaint(
      for: surface,
      capabilityProfile: capabilityProfile
    )
  }
}

/// A test must not start a program on the machine it runs on. With a host
/// opener in place the default open-link action hands the destination to the
/// surface, which declines it, and never spawns the platform's opener.
extension RunLoopTestHarnessSurface: LinkOpeningPresentationSurface {
  @MainActor var opensLinksInHost: Bool {
    true
  }

  @MainActor
  func openLinkInHost(_: LinkDestination) -> Bool {
    false
  }
}

/// The input source of a harness's run loop. The harness delivers events to
/// the run loop directly, so the stream is never read and has nothing in it.
private final class RunLoopTestHarnessInputReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

/// Why a harness call failed. A test reads the description: the type is not
/// part of the Testing SPI.
private enum RunLoopTestHarnessError: Error, CustomStringConvertible {
  case emptySurface(CellSize)
  case noFirstFrame
  case shutDown
  case reentrantCall
  case negativeDuration(Duration)
  case sceneDidNotSettle(MonotonicInstant)

  var description: String {
    switch self {
    case .emptySurface(let size):
      "RunLoopTestHarness: a surface of \(size.width) by \(size.height) cells has no cell to "
        + "present to. Both dimensions must be positive."
    case .noFirstFrame:
      "RunLoopTestHarness: the run loop presented no first frame."
    case .shutDown:
      "RunLoopTestHarness: the harness was shut down. It renders no further frame."
    case .reentrantCall:
      "RunLoopTestHarness: a call that renders was made while another call of the same "
        + "harness was rendering. Make the call after that one returns."
    case .negativeDuration(let duration):
      "RunLoopTestHarness: the clock cannot move back by \(duration)."
    case .sceneDidNotSettle(let instant):
      "RunLoopTestHarness: the scene still has a frame due at \(instant.offset) after "
        + "\(maximumRenderPassesAtOneInstant) render passes at that instant. A view that "
        + "changes its own state on every frame never settles."
    }
  }
}
