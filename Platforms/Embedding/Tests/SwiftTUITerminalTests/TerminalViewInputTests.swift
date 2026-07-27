import SwiftTUICore
import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUITerminal

@MainActor
@Suite("TerminalView input")
struct TerminalViewInputTests {
  @Test("configured host interception consumes Escape before the child")
  func hostInterceptionConsumesEscape() async throws {
    let session = RecordingTerminalSession()
    let routedKeyPresses = Mutex<[KeyPress]>([])
    let runLoop = try makeTerminalViewRunLoop(
      TerminalView(
        session: session,
        keyRouting: { keyPress in
          routedKeyPresses.withLock { $0.append(keyPress) }
          return keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
        }
      )
    )

    #expect(runLoop.handleKeyPress(KeyPress(.escape)) == nil)
    await Task.yield()
    #expect(routedKeyPresses.withLock { $0 } == [KeyPress(.escape)])
    #expect(session.sentKeys.isEmpty)
  }

  @Test("default key routing forwards Escape to the child")
  func defaultRoutingForwardsEscape() async throws {
    let session = RecordingTerminalSession()
    let runLoop = try makeTerminalViewRunLoop(TerminalView(session: session))

    #expect(runLoop.handleKeyPress(KeyPress(.escape)) == nil)
    await session.sentKeySignal.wait {
      session.sentKeys == [TerminalEmulatorKey(code: .escape)]
    }

    #expect(session.sentKeys == [TerminalEmulatorKey(code: .escape)])
  }

  @Test("host routing sees character, navigation, and modified input before conversion")
  func hostRoutingSeesOriginalKeyPresses() async throws {
    let session = RecordingTerminalSession()
    let routedKeyPresses = Mutex<[KeyPress]>([])
    let runLoop = try makeTerminalViewRunLoop(
      TerminalView(
        session: session,
        keyRouting: { keyPress in
          routedKeyPresses.withLock { $0.append(keyPress) }
          return .forwardToChild
        }
      )
    )
    let keyPresses = [
      KeyPress(.character("x")),
      KeyPress(.pageDown),
      KeyPress(.character("c"), modifiers: [.ctrl, .alt, .shift]),
    ]

    for keyPress in keyPresses {
      #expect(runLoop.handleKeyPress(keyPress) == nil)
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
  func forwardedUnmappableInputRemainsIgnored() throws {
    let session = RecordingTerminalSession()
    let routedKeyPresses = Mutex<[KeyPress]>([])
    let runLoop = try makeTerminalViewRunLoop(
      TerminalView(
        session: session,
        keyRouting: { keyPress in
          routedKeyPresses.withLock { $0.append(keyPress) }
          return .forwardToChild
        }
      )
    )
    let invalidFunctionKey = KeyPress(.functionKey(0))

    #expect(TerminalEmulatorKey(keyPress: invalidFunctionKey) == nil)
    #expect(runLoop.handleKeyPress(invalidFunctionKey) == nil)
    #expect(routedKeyPresses.withLock { $0 } == [invalidFunctionKey])
    #expect(session.sentKeys.isEmpty)
  }

  @Test("host-focused terminal routes through the framework member without state-slot aliasing")
  func hostFocusedTerminalRoutesThroughFrameworkMember() async throws {
    let session = RecordingTerminalSession()
    let routedKeyPresses = Mutex<[KeyPress]>([])
    let runLoop = try makeTerminalViewRunLoop(
      HostFocusedTerminalFixture(
        session: session,
        keyRouting: { keyPress in
          routedKeyPresses.withLock { $0.append(keyPress) }
          return keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
        }
      )
    )

    // The sibling owns initial focus, so terminal input must remain dormant.
    #expect(runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    await Task.yield()
    #expect(routedKeyPresses.withLock { $0 }.isEmpty)
    #expect(session.sentKeys.isEmpty)

    runLoop.focusTracker.focusNext()
    try settleTerminalViewRunLoop(runLoop)

    #expect(runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
    await session.sentKeySignal.wait {
      session.sentKeys == [TerminalEmulatorKey(code: .arrowDown)]
    }
    #expect(runLoop.handleKeyPress(KeyPress(.escape)) == nil)
    await Task.yield()

    #expect(routedKeyPresses.withLock { $0 } == [KeyPress(.arrowDown), KeyPress(.escape)])
    #expect(session.sentKeys == [TerminalEmulatorKey(code: .arrowDown)])

    runLoop.focusTracker.focusPrevious()
    try settleTerminalViewRunLoop(runLoop)
    #expect(runLoop.handleKeyPress(KeyPress(.arrowDown)) == nil)
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
) throws -> SwiftTUIRuntime.RunLoop<Int, Content> {
  let terminalSize = CellSize(width: 20, height: 4)
  let rootIdentity = Identity(components: [.named("TerminalViewInputRoot")])
  let runLoop = SwiftTUIRuntime.RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: TerminalViewInputHost(surfaceSize: terminalSize),
    terminalInputReader: TerminalViewInputReader(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    proposal: ProposedSize(width: terminalSize.width, height: terminalSize.height),
    exitKeyBindings: .none,
    viewBuilder: { _, _ in terminalView }
  )
  runLoop.installFocusTrackerInvalidator()
  runLoop.scheduler.requestInvalidation(of: [rootIdentity])

  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
  for _ in 0..<5 {
    let previousFrameCount = renderedFrames
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    if previousFrameCount == renderedFrames {
      break
    }
  }
  return runLoop
}

@MainActor
private func settleTerminalViewRunLoop<State, Content: View>(
  _ runLoop: SwiftTUIRuntime.RunLoop<State, Content>
) throws {
  var renderedFrames = 0
  for _ in 0..<5 {
    let previousFrameCount = renderedFrames
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    if previousFrameCount == renderedFrames {
      break
    }
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
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class TerminalViewInputHost: PresentationSurface {
  var surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
}
