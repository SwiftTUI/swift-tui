import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct AccessibilityRuntimePolicyTests {
  @Test("focused node uses cursorAnchor when present")
  func focusedNodeUsesCursorAnchor() {
    let focusedID = testIdentity("Focused")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: focusedID,
          rect: rect(x: 2, y: 3, width: 8, height: 1),
          role: .button,
          cursorAnchor: CellPoint(x: 6, y: 3)
        )
      ]
    )

    let point = AccessibilityRuntimePolicy().focusedCursorPoint(
      in: snapshot,
      focusedIdentity: focusedID
    )

    #expect(point == CellPoint(x: 6, y: 3))
  }

  @Test("focused node without cursorAnchor falls back to rect origin")
  func focusedNodeWithoutCursorAnchorFallsBackToOrigin() {
    let focusedID = testIdentity("Focused")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: focusedID,
          rect: rect(x: 4, y: 5, width: 8, height: 1),
          role: .button
        )
      ]
    )

    let point = AccessibilityRuntimePolicy().focusedCursorPoint(
      in: snapshot,
      focusedIdentity: focusedID
    )

    #expect(point == CellPoint(x: 4, y: 5))
  }

  @Test("missing focused accessibility node yields no cursor point")
  func missingFocusedAccessibilityNodeYieldsNil() {
    let focusedID = testIdentity("Hidden")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: testIdentity("Visible"),
          rect: rect(x: 0, y: 0, width: 8, height: 1),
          role: .button
        )
      ]
    )

    let point = AccessibilityRuntimePolicy().focusedCursorPoint(
      in: snapshot,
      focusedIdentity: focusedID
    )

    #expect(point == nil)
  }

  @Test("unfocused frame yields no cursor point")
  func unfocusedFrameYieldsNil() {
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: testIdentity("Visible"),
          rect: rect(x: 0, y: 0, width: 8, height: 1),
          role: .button
        )
      ]
    )

    let point = AccessibilityRuntimePolicy().focusedCursorPoint(
      in: snapshot,
      focusedIdentity: nil
    )

    #expect(point == nil)
  }

  @Test("run loop leaves terminal cursor untouched by default after presenting focused control")
  func runLoopLeavesCursorUntouchedByDefault() throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("CursorFocusRoot")
    let buttonID = testIdentity("CursorFocusButton")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker
    ) {
      Button("Run") {}
        .id(buttonID)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(focusTracker.currentFocusIdentity == buttonID)
    #expect(terminal.movedCursorPoints.isEmpty)
    #expect(!terminal.writes.contains("\u{001B}[?25h"))
    #expect(!terminal.writes.contains("\u{001B}[?25l"))
  }

  @Test("run loop moves and shows terminal cursor when cursor focus-following is enabled")
  func runLoopMovesCursorWhenFocusFollowingEnabled() throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("EnabledCursorFocusRoot")
    let buttonID = testIdentity("EnabledCursorFocusButton")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      Button("Run") {}
        .id(buttonID)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let expected = try #require(
      AccessibilityRuntimePolicy().focusedCursorPoint(
        in: runLoop.latestSemanticSnapshot,
        focusedIdentity: focusTracker.currentFocusIdentity
      )
    )

    #expect(focusTracker.currentFocusIdentity == buttonID)
    #expect(terminal.movedCursorPoints.last == expected)
    #expect(terminal.writes.contains("\u{001B}[?25h"))
  }

  @Test("run loop skips cursor focus-following outside TUI output")
  func runLoopSkipsCursorFocusFollowingOutsideTUIOutput() throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("JSONCursorFocusRoot")
    let buttonID = testIdentity("JSONCursorFocusButton")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(output: .json, cursorFollowsFocus: true)
    ) {
      Button("Run") {}
        .id(buttonID)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(focusTracker.currentFocusIdentity == buttonID)
    #expect(terminal.movedCursorPoints.isEmpty)
    #expect(!terminal.writes.contains("\u{001B}[?25h"))
    #expect(!terminal.writes.contains("\u{001B}[?25l"))
  }

  @Test("run loop hides cursor when focused control is accessibility hidden")
  func runLoopHidesCursorForHiddenFocusedControl() throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("HiddenCursorFocusRoot")
    let hiddenID = testIdentity("HiddenCursorFocusButton")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      Button("Hidden") {}
        .id(hiddenID)
        .accessibilityHidden()
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(focusTracker.currentFocusIdentity == hiddenID)
    #expect(
      AccessibilityRuntimePolicy().focusedCursorPoint(
        in: runLoop.latestSemanticSnapshot,
        focusedIdentity: focusTracker.currentFocusIdentity
      ) == nil
    )
    #expect(terminal.movedCursorPoints.isEmpty)
    #expect(terminal.writes.contains("\u{001B}[?25l"))
  }

  @Test("run loop hides cursor for unfocused frames")
  func runLoopHidesCursorForUnfocusedFrame() throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("UnfocusedCursorRoot")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      Text("Static")
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(focusTracker.currentFocusIdentity == nil)
    #expect(terminal.movedCursorPoints.isEmpty)
    #expect(terminal.writes.contains("\u{001B}[?25l"))
  }

  @Test("run loop anchors cursor-following to a TextField caret")
  func runLoopAnchorsCursorFollowingToTextFieldCaret() throws {
    let terminalSize = CellSize(width: 32, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("TextFieldCursorRoot")
    let textFieldID = testIdentity("TextFieldCursor")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      TextField("Name", text: .constant("abc"))
        .id(textFieldID)
        .frame(width: 14)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let node = try #require(
      runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.identity == textFieldID }
    )
    let cursorAnchor = try #require(node.cursorAnchor)

    #expect(focusTracker.currentFocusIdentity == textFieldID)
    #expect(cursorAnchor != node.rect.origin)
    #expect(terminal.movedCursorPoints.last == cursorAnchor)
    #expect(!(terminal.latestSurface?.lines.joined(separator: "\n").contains("abc_") ?? false))
  }

  @Test("run loop anchors cursor-following to a SecureField caret without exposing value")
  func runLoopAnchorsCursorFollowingToSecureFieldCaret() throws {
    let terminalSize = CellSize(width: 32, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("SecureFieldCursorRoot")
    let secureFieldID = testIdentity("SecureFieldCursor")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      SecureField("Password", text: .constant("secret"))
        .id(secureFieldID)
        .frame(width: 16)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let node = try #require(
      runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.identity == secureFieldID }
    )
    let cursorAnchor = try #require(node.cursorAnchor)
    let surface = terminal.latestSurface?.lines.joined(separator: "\n") ?? ""

    #expect(focusTracker.currentFocusIdentity == secureFieldID)
    #expect(terminal.movedCursorPoints.last == cursorAnchor)
    #expect(!surface.contains("secret"))
    #expect(
      !String(describing: runLoop.latestSemanticSnapshot.accessibilityNodes).contains("secret"))
  }

  @Test("run loop anchors cursor-following to a TextEditor caret")
  func runLoopAnchorsCursorFollowingToTextEditorCaret() throws {
    let terminalSize = CellSize(width: 32, height: 8)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("TextEditorCursorRoot")
    let textEditorID = testIdentity("TextEditorCursor")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker,
      runtimeConfiguration: .init(cursorFollowsFocus: true)
    ) {
      TextEditor(text: .constant("a\nbc"))
        .id(textEditorID)
        .frame(width: 16, height: 5)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let node = try #require(
      runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.identity == textEditorID }
    )
    let cursorAnchor = try #require(node.cursorAnchor)

    #expect(focusTracker.currentFocusIdentity == textEditorID)
    #expect(cursorAnchor != node.rect.origin)
    #expect(terminal.movedCursorPoints.last == cursorAnchor)
    #expect(!(terminal.latestSurface?.lines.joined(separator: "\n").contains("bc_") ?? false))
  }
}

@MainActor
private func cursorFocusRunLoop<Content: View>(
  rootIdentity: Identity,
  terminal: CursorFocusTestTerminalHost,
  terminalSize: CellSize,
  focusTracker: FocusTracker,
  runtimeConfiguration: RuntimeConfiguration = .default,
  @ViewBuilder view: @escaping () -> Content
) -> RunLoop<Int, Content> {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = terminal.appearance
  environmentValues.terminalSize = terminalSize

  let runLoop = RunLoop<Int, Content>(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: CursorFocusTestInputReader(),
    signalReader: CursorFocusTestSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    runtimeConfiguration: runtimeConfiguration,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: ScopedMapper { _ in view() }
  )
  return runLoop
}

private final class CursorFocusTestTerminalHost: PresentationSurface,
  DamageAwarePresentationSurface, TerminalCursorFocusPresentationSurface
{
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private(set) var movedCursorPoints: [CellPoint] = []
  private(set) var writes: [String] = []
  private let surfaceSizeProvider: () -> CellSize

  init(
    surfaceSizeProvider: @escaping () -> CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ output: String) throws { writes.append(output) }
  func clearScreen() throws {}
  func moveCursor(to point: CellPoint) throws { movedCursorPoints.append(point) }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage _: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    try present(surface)
  }
}

private final class CursorFocusTestInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { $0.finish() }
  }
}

private final class CursorFocusTestSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}

private func rect(
  x: Int,
  y: Int,
  width: Int,
  height: Int
) -> CellRect {
  CellRect(
    origin: CellPoint(x: x, y: y),
    size: CellSize(width: width, height: height)
  )
}
