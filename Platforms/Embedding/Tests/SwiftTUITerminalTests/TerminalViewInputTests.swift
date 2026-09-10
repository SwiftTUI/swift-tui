// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  import SwiftTUIRuntime
  @_spi(Testing) import SwiftTUITestSupport
  import Synchronization
  import Testing

  @testable import SwiftTUITerminal

  @MainActor
  @Suite("TerminalView input", .timeLimit(.minutes(1)))
  struct TerminalViewInputTests {
    @Test("configured host interception consumes Escape before the child")
    func hostInterceptionConsumesEscape() async throws {
      let session = RecordingTerminalSession()
      let routedKeyPresses = Mutex<[KeyPress]>([])
      let runLoop = await makeTerminalViewRunLoop(
        TerminalView(
          session: session,
          keyRouting: { keyPress in
            routedKeyPresses.withLock { $0.append(keyPress) }
            return keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
          }
        )
      )

      defer { runLoop.stop() }

      await runLoop.press(KeyPress(.escape))
      await Task.yield()
      #expect(routedKeyPresses.withLock { $0 } == [KeyPress(.escape)])
      #expect(session.sentKeys.isEmpty)
    }

    @Test("default key routing forwards Escape to the child")
    func defaultRoutingForwardsEscape() async throws {
      let session = RecordingTerminalSession()
      let runLoop = await makeTerminalViewRunLoop(TerminalView(session: session))

      defer { runLoop.stop() }

      await runLoop.press(KeyPress(.escape))
      await session.sentKeySignal.wait {
        session.sentKeys == [TerminalEmulatorKey(code: .escape)]
      }

      #expect(session.sentKeys == [TerminalEmulatorKey(code: .escape)])
    }

    @Test("host routing sees character, navigation, and modified input before conversion")
    func hostRoutingSeesOriginalKeyPresses() async throws {
      let session = RecordingTerminalSession()
      let routedKeyPresses = Mutex<[KeyPress]>([])
      let runLoop = await makeTerminalViewRunLoop(
        TerminalView(
          session: session,
          keyRouting: { keyPress in
            routedKeyPresses.withLock { $0.append(keyPress) }
            return .forwardToChild
          }
        )
      )
      defer { runLoop.stop() }

      let keyPresses = [
        KeyPress(.character("x")),
        KeyPress(.pageDown),
        KeyPress(.character("c"), modifiers: [.ctrl, .alt, .shift]),
      ]

      for keyPress in keyPresses {
        await runLoop.press(keyPress)
      }
      await session.sentKeySignal.wait {
        session.sentKeys.count == keyPresses.count
      }

      #expect(routedKeyPresses.withLock { $0 } == keyPresses)
      #expect(
        Set(session.sentKeys)
          == Set([
            TerminalEmulatorKey(code: .character("x")),
            TerminalEmulatorKey(code: .pageDown),
            TerminalEmulatorKey(
              code: .character("c"),
              modifiers: [.control, .option, .shift]
            ),
          ])
      )
    }

    @Test("forwarded unmappable input remains ignored")
    func forwardedUnmappableInputRemainsIgnored() async throws {
      let session = RecordingTerminalSession()
      let routedKeyPresses = Mutex<[KeyPress]>([])
      let runLoop = await makeTerminalViewRunLoop(
        TerminalView(
          session: session,
          keyRouting: { keyPress in
            routedKeyPresses.withLock { $0.append(keyPress) }
            return .forwardToChild
          }
        )
      )
      defer { runLoop.stop() }

      let invalidFunctionKey = KeyPress(.functionKey(0))

      #expect(TerminalEmulatorKey(keyPress: invalidFunctionKey) == nil)
      await runLoop.press(invalidFunctionKey)
      #expect(routedKeyPresses.withLock { $0 } == [invalidFunctionKey])
      #expect(session.sentKeys.isEmpty)
    }

    @Test("host-focused terminal routes through the framework member without state-slot aliasing")
    func hostFocusedTerminalRoutesThroughFrameworkMember() async throws {
      let session = RecordingTerminalSession()
      let routedKeyPresses = Mutex<[KeyPress]>([])
      let runLoop = await makeTerminalViewRunLoop(
        HostFocusedTerminalFixture(
          session: session,
          keyRouting: { keyPress in
            routedKeyPresses.withLock { $0.append(keyPress) }
            return keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
          }
        )
      )

      defer { runLoop.stop() }

      // The sibling owns initial focus, so terminal input must remain dormant.
      await runLoop.press(KeyPress(.arrowDown))
      await Task.yield()
      #expect(routedKeyPresses.withLock { $0 }.isEmpty)
      #expect(session.sentKeys.isEmpty)

      runLoop.focusTracker.focusNext()
      await runLoop.settle()

      await runLoop.press(KeyPress(.arrowDown))
      await session.sentKeySignal.wait {
        session.sentKeys == [TerminalEmulatorKey(code: .arrowDown)]
      }
      await runLoop.press(KeyPress(.escape))
      await Task.yield()

      #expect(routedKeyPresses.withLock { $0 } == [KeyPress(.arrowDown), KeyPress(.escape)])
      #expect(session.sentKeys == [TerminalEmulatorKey(code: .arrowDown)])

      runLoop.focusTracker.focusPrevious()
      await runLoop.settle()
      await runLoop.press(KeyPress(.arrowDown))
      await Task.yield()
      #expect(routedKeyPresses.withLock { $0 } == [KeyPress(.arrowDown), KeyPress(.escape)])
      #expect(session.sentKeys == [TerminalEmulatorKey(code: .arrowDown)])
    }

    @Test("maps focused character key presses to emulator keys")
    func mapsCharacterKeyPresses() {
      #expect(
        TerminalEmulatorKey(keyPress: KeyPress(.character("a")))
          == TerminalEmulatorKey(code: .character("a"))
      )
      #expect(
        TerminalEmulatorKey(
          keyPress: KeyPress(
            .character("z"),
            modifiers: [.ctrl, .alt, .shift]
          )
        )
          == TerminalEmulatorKey(
            code: .character("z"),
            modifiers: [.control, .option, .shift]
          )
      )
    }

    @Test("maps focused navigation key presses to emulator keys")
    func mapsNavigationKeyPresses() {
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.return))?.code == .enter)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.space))?.code == .character(" "))
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.tab))?.code == .tab)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.escape))?.code == .escape)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.backspace))?.code == .backspace)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowUp))?.code == .arrowUp)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowDown))?.code == .arrowDown)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowLeft))?.code == .arrowLeft)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.arrowRight))?.code == .arrowRight)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.home))?.code == .home)
      #expect(TerminalEmulatorKey(keyPress: KeyPress(.end))?.code == .end)
    }
  }

  @MainActor
  private func makeTerminalViewRunLoop<Content: View>(
    _ terminalView: Content
  ) async -> TerminalViewInputHarness {
    let harness = TerminalViewInputHarness()
    let rootIdentity = Identity(components: [.named("TerminalViewInputRoot")])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: harness.host,
      terminalInputReader: harness.input,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: harness.focusTracker,
      proposal: ProposedSize(width: 20, height: 4),
      exitKeyBindings: .none,
      viewBuilder: { _, _ in
        Panel(id: "input-root") { terminalView }
          .keyCommand("Test input barrier", key: .functionKey(99), modifiers: []) {
            harness.barriers += 1
            harness.barrierSignal.notify()
          }
      }
    )
    harness.task = Task { _ = try await runLoop.run() }
    let host = harness.host
    await host.frameSignal.wait { host.frames > 0 }
    return harness
  }

  /// Drives the public input stream. A scoped command acknowledges each batch
  /// before assertions, without exposing the runtime's private dispatch methods.
  @MainActor
  private final class TerminalViewInputHarness {
    let input = TerminalViewInputReader()
    let host = TerminalViewInputHost(surfaceSize: CellSize(width: 20, height: 4))
    let focusTracker = FocusTracker(
      invalidationIdentities: [Identity(components: [.named("TerminalViewInputRoot")])]
    )
    let barrierSignal = MainActorConditionSignal()
    var barriers = 0
    var task: Task<Void, any Error>?

    func press(_ key: KeyPress) async {
      input.send(key)
      await settle()
    }

    func settle() async {
      let target = barriers + 1
      let host = self.host
      let previousFrames = host.frames
      input.send(KeyPress(.functionKey(99)))
      await barrierSignal.wait { self.barriers >= target }
      await host.frameSignal.wait { host.frames > previousFrames }
    }

    func stop() {
      input.finish()
      task?.cancel()
    }
  }

  private enum HostFocusedTerminalFixtureFocus: Hashable {
    case browser
    case preview
  }

  @MainActor
  private struct HostFocusedTerminalFixture: View {
    // Deliberately collides with TerminalView.updateGeneration's authored slot
    // ordinal. The host-focused boundary must keep these differently typed slots
    // on distinct identities.
    @FocusState(line: 13, column: 3) private var focus: HostFocusedTerminalFixtureFocus?

    let session: RecordingTerminalSession
    let keyRouting: @MainActor @Sendable (KeyPress) -> TerminalViewKeyDisposition

    var body: some View {
      HStack {
        Text("Browser")
          .focusable(true)
          .focused($focus, equals: .browser)
        TerminalView(
          session: session,
          keyRouting: keyRouting
        )
        .hostFocused($focus, equals: .preview)
      }
      .defaultFocus($focus, .browser)
    }
  }

  private final class RecordingTerminalSession: TerminalSession {
    private let sentKeyStorage = Mutex<[TerminalEmulatorKey]>([])
    let sentKeySignal = ConditionSignal()

    var sentKeys: [TerminalEmulatorKey] {
      sentKeyStorage.withLock { $0 }
    }

    var cachedSnapshot: ForeignGrid {
      .empty
    }

    func start() async throws {}

    func snapshot() async -> ForeignGrid {
      cachedSnapshot
    }

    func currentTitle() async -> String? {
      nil
    }

    func currentWorkingDirectory() async -> String? {
      nil
    }

    func currentLifecycle() async -> TerminalLifecycle {
      .notStarted
    }

    func send(key: TerminalEmulatorKey) async {
      sentKeyStorage.withLock { $0.append(key) }
      sentKeySignal.notify()
    }

    func send(paste _: String) async {}

    func send(mouse _: TerminalEmulatorMouse) async {}

    func resize(_: CellSize) async throws {}

    func events() -> AsyncStream<TerminalEmulatorEvent> {
      AsyncStream { $0.finish() }
    }
  }

  private final class TerminalViewInputReader: TerminalInputReading {
    private let pair = AsyncStream<InputEvent>.makeStream()

    func inputEvents() -> AsyncStream<InputEvent> { pair.stream }
    func send(_ key: KeyPress) { pair.continuation.yield(.key(key)) }
    func finish() { pair.continuation.finish() }
  }

  private final class TerminalViewInputHost: PresentationSurface, Sendable {
    private let frameStorage = Mutex(0)
    let frameSignal = ConditionSignal()
    var frames: Int { frameStorage.withLock { $0 } }
    let surfaceSize: CellSize
    let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
    let appearance: TerminalAppearance = .fallback

    init(surfaceSize: CellSize) {
      self.surfaceSize = surfaceSize
    }

    func enableRawMode() throws {}
    func disableRawMode() throws {}
    func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
      frameStorage.withLock { $0 += 1 }
      frameSignal.notify()
      return TerminalPresentationMetrics(linesTouched: surface.size.height)
    }
    func write(_: String) throws {}
    func clearScreen() throws {}
    func moveCursor(to _: CellPoint) throws {}
  }

#endif
