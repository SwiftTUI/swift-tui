import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
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

  @Test(
    "run loop leaves terminal cursor untouched by default for focus without a text caret",
    arguments: [false, true])
  func runLoopLeavesCursorUntouchedForCaretlessFocusByDefault(
    authoredCursorAnchor: Bool
  ) throws {
    let terminalSize = CellSize(width: 24, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("CaretlessCursorRoot")
    let focusedID = testIdentity("CaretlessCursorFocus")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker
    ) {
      // An editing control without a caret, or an authored cursor anchor,
      // which the terminal uses only when cursor-following is enabled.
      if authoredCursorAnchor {
        Button("Run") {}
          .accessibilityCursorAnchor(CellPoint(x: 1, y: 0))
          .id(focusedID)
      } else {
        Slider("Volume", value: .constant(5), in: 0...10)
          .id(focusedID)
      }
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // Without a text caret there is no cursor to show, on the focusing
    // frame or after it.
    #expect(focusTracker.currentFocusIdentity == focusedID)
    #expect(runLoop.currentFocusPresentation.prefersTextInput == !authoredCursorAnchor)
    #expect(terminal.movedCursorPoints.isEmpty)
    #expect(!terminal.writes.contains("\u{001B}[?25h"))
    #expect(!terminal.writes.contains("\u{001B}[?25l"))
  }

  @Test("run loop shows terminal cursor at a SecureField caret by default")
  func runLoopShowsCursorAtSecureFieldCaretByDefault() throws {
    let terminalSize = CellSize(width: 32, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("DefaultSecureFieldCursorRoot")
    let secureFieldID = testIdentity("DefaultSecureFieldCursor")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker
    ) {
      SecureField("Password", text: .constant("secret"))
        .id(secureFieldID)
        .frame(width: 16)
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    // The secure field withholds `textInput` but still owns a text caret.
    let node = try #require(
      runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.identity == secureFieldID }
    )
    #expect(focusTracker.currentFocusIdentity == secureFieldID)
    #expect(node.textInput == nil)
    #expect(terminal.movedCursorPoints.last == node.cursorAnchor)
    #expect(terminal.writes.last == "\u{001B}[?25h")
  }

  @Test(
    "run loop hides the text caret cursor by default once focus leaves the field",
    arguments: [false, true])
  func runLoopHidesTextCaretCursorWhenFocusLeavesField(toValueControl: Bool) throws {
    let terminalSize = CellSize(width: 32, height: 6)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { terminalSize })
    let rootIdentity = testIdentity("CaretHandOffRoot")
    let fieldID = testIdentity("CaretHandOffField")
    let otherID = testIdentity("CaretHandOffOther")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = cursorFocusRunLoop(
      rootIdentity: rootIdentity,
      terminal: terminal,
      terminalSize: terminalSize,
      focusTracker: focusTracker
    ) {
      VStack {
        TextField("Name", text: .constant("abc"))
          .id(fieldID)
          .frame(width: 14)
        if toValueControl {
          Slider("Volume", value: .constant(5), in: 0...10)
            .id(otherID)
        } else {
          Button("Run") {}
            .id(otherID)
        }
      }
    }

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(focusTracker.currentFocusIdentity == fieldID)
    #expect(terminal.writes.last == "\u{001B}[?25h")

    // The caret this policy showed must not linger once focus moves to a
    // control without one.
    _ = focusTracker.setFocus(to: otherID)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(focusTracker.currentFocusIdentity == otherID)
    #expect(terminal.writes.last == "\u{001B}[?25l")

    // With the caret hidden, later frames leave the cursor untouched.
    let writesAfterHide = terminal.writes.count
    let cursorMovesAfterHide = terminal.movedCursorPoints.count
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(terminal.writes.count == writesAfterHide)
    #expect(terminal.movedCursorPoints.count == cursorMovesAfterHide)
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
    #expect(node.textInput?.selection == 3..<3)
    #expect(node.textInput?.endAnchor == cursorAnchor)
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
    #expect(node.textInput == nil)
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
    #expect(node.textInput?.selection == 4..<4)
    #expect(node.textInput?.endAnchor == cursorAnchor)
    #expect(node.textInput?.clusters.count == 4)
    _ = runLoop.handle(.input(.key(.init(.arrowLeft))))
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    let moved = try #require(
      runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.identity == textEditorID })
    #expect(moved.textInput?.selection == 3..<3)
    #expect(moved.cursorAnchor?.x == cursorAnchor.x - 1)
    #expect(cursorAnchor != node.rect.origin)
    #expect(terminal.movedCursorPoints.last == moved.cursorAnchor)
    #expect(!(terminal.latestSurface?.lines.joined(separator: "\n").contains("bc_") ?? false))
  }

  @Test("run loop prefers semantic host-frame surface over raster damage surface")
  func runLoopPrefersSemanticHostFrameSurfaceOverRasterDamageSurface() throws {
    let surface = SemanticHostFrameDispatchSurface()
    let rootIdentity = testIdentity("SemanticHostFrameDispatchRoot")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = semanticHostFrameDispatchRunLoop(
      rootIdentity: rootIdentity,
      surface: surface,
      focusTracker: focusTracker
    )

    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    let frame = try #require(surface.semanticFrames.last)
    #expect(surface.rasterOnlyPresentations == 0)
    #expect(surface.rasterDamagePresentations == 0)
    #expect(frame.sequence == 0)
    #expect(frame.raster.lines.joined(separator: "\n").contains("Run"))
    #expect(
      frame.semantics.focusRegions.map(\.identity).contains(testIdentity("SemanticHostButton")))
    #expect(frame.focusedIdentity == testIdentity("SemanticHostButton"))

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(surface.semanticFrames.count >= 2)
    let hasContiguousSequences = surface.semanticFrames.enumerated().allSatisfy { index, frame in
      frame.sequence == UInt64(index)
    }
    #expect(hasContiguousSequences)
  }

  @Test("run loop accepts semantic host-frame surfaces without terminal obligations")
  func runLoopAcceptsSemanticOnlyHostFrameSurface() throws {
    let surface = SemanticOnlyHostFrameSurface()
    let rootIdentity = testIdentity("SemanticOnlyRoot")
    let valueIdentity = testIdentity("SemanticOnlyValue")
    let stateContainer = StateContainer(
      initialState: 0,
      invalidationIdentities: [valueIdentity]
    )
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop<Int, SemanticOnlyStateView>(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: CursorFocusTestInputReader(),
      signalReader: CursorFocusTestSignalReader(),
      scheduler: FrameScheduler(),
      stateContainer: stateContainer,
      focusTracker: focusTracker,
      runtimeConfiguration: .default,
      proposal: .init(width: surface.surfaceSize.width, height: surface.surfaceSize.height),
      viewBuilder: ScopedMapper { input in
        SemanticOnlyStateView(value: input.state, identity: valueIdentity)
      }
    )
    let erasedSurface: AnyObject = surface

    #expect(!(erasedSurface is any PresentationSurface))
    #expect(!(erasedSurface is any RasterPresentationSurface))
    #expect(!(erasedSurface is any TerminalCommandPresentationSurface))

    stateContainer.invalidator = runLoop.scheduler
    focusTracker.invalidator = runLoop.scheduler
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])

    var renderedFrames = 0
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    stateContainer.mutate { $0 = 1 }
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)

    #expect(surface.frames.count >= 2)
    let firstFrame = try #require(surface.frames.first)
    let secondFrame = try #require(surface.frames.last)
    #expect(firstFrame.sequence == 0)
    #expect(secondFrame.sequence == UInt64(surface.frames.count - 1))
    #expect(secondFrame.raster.lines.joined(separator: "\n").contains("Value 1"))
    #expect(
      secondFrame.semantics.focusRegions.map(\.identity).contains(valueIdentity)
    )
    #expect(secondFrame.focusedIdentity == valueIdentity)
    #expect(firstFrame.rasterDamage == nil)
  }
}

@MainActor
private func semanticHostFrameDispatchRunLoop(
  rootIdentity: Identity,
  surface: SemanticHostFrameDispatchSurface,
  focusTracker: FocusTracker
) -> RunLoop<Int, SemanticHostFrameButtonView> {
  RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: surface,
    terminalInputReader: CursorFocusTestInputReader(),
    signalReader: CursorFocusTestSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    runtimeConfiguration: .default,
    proposal: .init(width: surface.surfaceSize.width, height: surface.surfaceSize.height),
    viewBuilder: ScopedMapper { _ in
      SemanticHostFrameButtonView()
    }
  )
}

private struct SemanticHostFrameButtonView: View {
  var body: some View {
    Button("Run") {}
      .id(testIdentity("SemanticHostButton"))
  }
}

private struct SemanticOnlyStateView: View {
  var value: Int
  var identity: Identity

  var body: some View {
    Button("Value \(value)") {}
      .id(identity)
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

private final class SemanticHostFrameDispatchSurface:
  PresentationSurface, DamageAwarePresentationSurface, SemanticHostFramePresentationSurface
{
  let surfaceSize = CellSize(width: 24, height: 6)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let semanticHostFrameCapabilities: SemanticHostFrameCapabilities = []
  private(set) var semanticFrames: [SemanticHostFrame] = []
  private(set) var rasterOnlyPresentations = 0
  private(set) var rasterDamagePresentations = 0

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    rasterOnlyPresentations += 1
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: surface,
      damage: nil
    )
  }

  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    rasterDamagePresentations += 1
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: surface,
      damage: damage
    )
  }

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    semanticFrames.append(frame)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage
    )
  }
}

private final class SemanticOnlyHostFrameSurface:
  PresentationSurfaceMetricsProvider, SemanticHostFramePresentationSurface
{
  let surfaceSize = CellSize(width: 24, height: 6)
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let semanticHostFrameCapabilities: SemanticHostFrameCapabilities = .standard
  private(set) var frames: [SemanticHostFrame] = []

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    frames.append(frame)
    return TerminalPresentationMetrics.rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage
    )
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

@MainActor
@Suite("Semantic action dispatch")
struct AccessibilityActionRuntimeTests {
  @Test("A retained four-style form restores conditionally removed Picker options")
  func pickerConditionalRestore() throws {
    let root = testIdentity("PickerConditionalRoot")
    let size = CellSize(width: 160, height: 60)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) { PickerConditionalFixture() }
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)
    func send(_ name: String, _ action: AccessibilityAction) throws {
      let target = try #require(
        loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == name }?.actionTarget)
      _ = loop.handle(
        .input(.accessibility(.init(target: target, action: action, requestID: UInt64(frames)))))
      try loop.renderPendingFrames(renderedFrames: &frames)
    }
    for name in ["Inline mode", "Menu mode", "Radio mode", "Segmented mode"] {
      try send(name, .focus)
      let option = try #require(
        loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == name }?
          .control?.selection?.options.first { $0.label == "Second" })
      try send(name, .setValue(.text(option.id)))
    }
    let fourth = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == "Segmented mode" }?
        .control?.selection?.options.first { $0.label == "Fourth" })
    try send("Segmented mode", .setValue(.text(fourth.id)))
    try send("Reset choices", .focus)
    try send("Reset choices", .activate)
    try send("Toggle second choices", .focus)
    try send("Toggle second choices", .activate)
    try send("Toggle second choices", .activate)
    #expect(
      loop.latestSemanticSnapshot.accessibilityNodes.filter { $0.role == .picker }.allSatisfy {
        $0.control?.selection?.options.count == 4
      })
  }

  @Test("Picker choices route by live identity across styles and option changes", arguments: 0..<4)
  func pickerChoices(styleIndex: Int) throws {
    let styles: [AnyPickerStyle] = [.inline, .menu, .radioGroup, .segmented]
    let root = testIdentity("PickerAssistiveRoot")
    let size = CellSize(width: 70, height: 30)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    var selection = 1
    var writes = 0
    var options = [1, 2, 3]
    var disabled = false
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) {
      VStack {
        Picker(
          selection: Binding(
            get: { selection },
            set: {
              selection = $0
              writes += 1
            })
        ) {
          ForEach(options, id: \.self) { option in
            PickerOption("Visual \(option)", value: option)
              .accessibilityLabel("Choice \(option)")
              .disabled(option == 3)
          }
        } label: {
          HStack {
            Text("Choose")
            Text("mode")
          }
        }
        .pickerStyle(styles[styleIndex])
        .pickerViewportLineCount(3)
        .disabled(disabled)
        .id(testIdentity("Choice"))
        Picker("Other picker", selection: .constant(10)) {
          PickerOption("Ten", value: 10)
          PickerOption("Twenty", value: 20)
        }
      }
    }
    focus.invalidator = loop.scheduler
    var frames = 0
    func render() throws {
      loop.scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &frames)
    }
    func node() throws -> AccessibilityNode {
      try #require(
        loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == "Choose mode" })
    }
    func choices() throws -> [AccessibilitySelectionOption] {
      try #require(node().control?.selection?.options)
    }
    func send(_ token: String) throws -> AccessibilityActionResult {
      loop.handleAccessibilityAction(
        .init(
          target: try #require(node().actionTarget), action: .setValue(.text(token))))
    }
    try render()
    let initial = try choices()
    if styleIndex == 1 {
      let collapsed = try node().rect
      #expect(collapsed.size.height == 1)
      let target = try #require(node().actionTarget)
      #expect(loop.handleAccessibilityAction(.init(target: target, action: .focus)) == .accepted)
      try render()
      #expect(try node().rect == collapsed)
      #expect(writes == 0)
    }
    if styleIndex >= 2 {
      let picker = try node()
      #expect(picker.selectionOptionRects.count == initial.count)
      for option in initial {
        let bounds = try #require(picker.selectionOptionRects[option.id])
        // The label and border are not options, including for disabled rows.
        #expect(bounds.origin.y > picker.rect.origin.y)
        #expect(bounds.size.height == 1)
        #expect(bounds.origin.x > picker.rect.origin.x)
      }
      let firstBounds = try #require(picker.selectionOptionRects[initial[0].id])
      let secondBounds = try #require(picker.selectionOptionRects[initial[1].id])
      #expect(firstBounds.intersection(secondBounds) == nil)
    }
    #expect(initial.map(\.label) == ["Choice 1", "Choice 2", "Choice 3"])
    #expect(initial.map(\.isEnabled) == [true, true, false])
    #expect(try node().control?.value == .text(initial[0].id))
    #expect(try send(initial[1].id) == .accepted)
    #expect(selection == 2 && writes == 1)
    try render()
    #expect(try choices() == initial)
    #expect(try node().control?.value == .text(initial[1].id))
    #expect(try send(initial[1].id) == .accepted)
    #expect(writes == 1)
    #expect(try send(initial[2].id) == .invalidValue)
    #expect(try send("not-an-option") == .invalidValue)
    #expect(writes == 1)
    options = [3, 2, 1]
    try render()
    #expect(try choices().map(\.id) == initial.reversed().map(\.id))
    options = [3, 1]
    try render()
    #expect(try send(initial[1].id) == .invalidValue)
    options = [3, 2, 1]
    try render()
    #expect(try choices()[1].id != initial[1].id)
    #expect(try send(initial[1].id) == .invalidValue)
    disabled = true
    try render()
    if styleIndex >= 2 {
      #expect(try node().selectionOptionRects.count == options.count)
    }
    #expect(try send(initial[0].id) == .disabled)
    #expect(writes == 1)
  }

  @Test("Rejected and no-op correlated requests still publish an acknowledgement")
  func actionAcknowledgements() throws {
    let surface = SemanticHostFrameDispatchSurface()
    let root = testIdentity("SemanticHostFrameDispatchRoot")
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = semanticHostFrameDispatchRunLoop(
      rootIdentity: root, surface: surface, focusTracker: focus)
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)
    _ = loop.handle(
      .input(.accessibility(.init(target: "missing", action: .activate, requestID: 1))))
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(
      surface.semanticFrames.last?.semantics.accessibilityActionResponse
        == .init(requestID: 1, target: "missing", result: .staleTarget))
    let target = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .button
      }?.actionTarget)
    _ = loop.handle(.input(.accessibility(.init(target: target, action: .focus, requestID: 2))))
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(
      surface.semanticFrames.last?.semantics.accessibilityActionResponse
        == .init(requestID: 2, target: target, result: .accepted))
  }

  @Test("Assistive requests reach retained controls and publish typed values")
  func retainedControlActions() throws {
    let root = testIdentity("AssistiveRoot")
    let size = CellSize(width: 60, height: 24)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) { AssistiveControls() }
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)

    func node(_ name: String) throws -> AccessibilityNode {
      try #require(
        loop.latestSemanticSnapshot.accessibilityNodes.first {
          $0.identity == testIdentity(name)
        })
    }
    func request(_ name: String, _ action: AccessibilityAction) throws
      -> AccessibilityActionResult
    {
      loop.handleAccessibilityAction(
        .init(target: try #require(node(name).actionTarget), action: action))
    }
    #expect(try request("ReadOnly", .focus) == .accepted)
    #expect(try request("ReadOnly", .setValue(.text("must not mutate"))) == .unsupported)
    #expect(try node("Name").control?.value == .text(""))
    let sliderTarget = try #require(node("Gain").actionTarget)
    #expect(try request("Toggle", .activate) == .accepted)
    #expect(try request("Gain", .increment) == .accepted)
    #expect(try request("Count", .decrement) == .accepted)
    #expect(try request("Name", .setValue(.text("Ada"))) == .accepted)
    #expect(try request("Secret", .setValue(.text("hidden value"))) == .accepted)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(try node("Toggle").control?.value == .boolean(true))
    #expect(try node("Gain").control?.value == .number(3))
    #expect(try node("Count").control?.value == .number(4))
    #expect(try node("Name").control?.value == .text("Ada"))
    #expect(try node("Secret").control?.value == nil)
    #expect(!String(describing: loop.latestSemanticSnapshot).contains("hidden value"))
    #expect(try node("Gain").actionTarget == sliderTarget)
    #expect(try request("Gain", .setValue(.number(8))) == .accepted)
    #expect(try request("Toggle", .setValue(.boolean(false))) == .accepted)
    #expect(try request("Name", .focus) == .accepted)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(focus.currentFocusIdentity == testIdentity("Name"))
    #expect(try node("Gain").control?.value == .number(8))
    #expect(try node("Toggle").control?.value == .boolean(false))
    let priorFrames = frames
    #expect(try request("Name", .focus) == .accepted)
    #expect(try request("Name", .setValue(.text("Ada"))) == .accepted)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(frames == priorFrames)

    #expect(try request("Disabled", .activate) == .disabled)
    #expect(try request("Gain", .activate) == .unsupported)
    #expect(try request("Gain", .setValue(.text("bad"))) == .invalidValue)
    #expect(try request("Gain", .setValue(.number(.nan))) == .invalidValue)
    #expect(try request("Gain", .setValue(.number(11))) == .invalidValue)
    #expect(try request("Gain", .setValue(.number(2.5))) == .invalidValue)
    #expect(
      loop.handleAccessibilityAction(.init(target: "missing", action: .activate)) == .staleTarget)

    _ = try request("Visibility", .activate)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(
      loop.handleAccessibilityAction(.init(target: sliderTarget, action: .increment))
        == .staleTarget)
    _ = try request("Visibility", .activate)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(try node("Gain").actionTarget != sliderTarget)
    #expect(
      loop.handleAccessibilityAction(.init(target: sliderTarget, action: .increment))
        == .staleTarget)
    let button = try #require(node("Toggle").actionTarget)
    _ = loop.handle(.input(.accessibility(.init(target: button, action: .activate))))
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(try node("Toggle").control?.value == .boolean(true))
    _ = try request("Modal", .activate)
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(try request("Toggle", .activate) == .outOfScope)
    #expect(try request("ModalChild", .focus) == .accepted)
  }

  @Test(
    "Assistive steps in a bounds-blocked direction leave an out-of-range Stepper model untouched",
    arguments: 0..<4)
  func blockedAssistiveStepperStepPreservesOutOfRangeModel(combination: Int) throws {
    let useDouble = combination % 2 == 1
    let below = combination / 2 == 1
    let raw = below ? -5 : 10
    let integer = AssistiveValueProbe(raw)
    let floating = AssistiveValueProbe(Double(raw))
    let root = testIdentity("AssistiveBoundsRoot")
    let size = CellSize(width: 40, height: 4)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) {
      if useDouble {
        Stepper("Bounded", value: floating.binding(), in: 0.0...5.0).id(testIdentity("Bounded"))
      } else {
        Stepper("Bounded", value: integer.binding(), in: 0...5).id(testIdentity("Bounded"))
      }
    }
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)

    let target = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.identity == testIdentity("Bounded")
      }?.actionTarget)
    let result = loop.handleAccessibilityAction(
      .init(target: target, action: below ? .decrement : .increment))
    try loop.renderPendingFrames(renderedFrames: &frames)

    #expect(result == .accepted)
    #expect(integer.value == raw)
    #expect(floating.value == Double(raw))
    #expect(integer.writes.isEmpty)
    #expect(floating.writes.isEmpty)
  }
}

@MainActor
@Suite("Public custom assistive actions")
struct CustomAccessibilityActionTests {
  @Test func inlineLinksUseTheirExistingTypedActionRoutes() throws {
    let calls = AssistiveValueProbe(0)
    let root = testIdentity("InlineLinks")
    let size = CellSize(width: 60, height: 10)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) {
      Text("Read \(Link("Guide", destination: "https://example.com/guide")) now.")
        .openLinkAction(
          OpenLinkAction { _ in
            calls.value += 1
            return true
          })
    }
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)
    let link = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first { $0.role == .link })
    let target = try #require(link.actionTarget)
    #expect(link.control?.opensLink == false)
    #expect(loop.handleAccessibilityAction(.init(target: target, action: .activate)) == .accepted)
    #expect(calls.value == 1)
  }

  @Test func primitiveAndAuthoredActivationRemainIndependent() throws {
    let calls = AssistiveValueProbe(0)
    let root = testIdentity("AuthoredButton")
    let size = CellSize(width: 40, height: 10)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) {
      VStack {
        Button("Original") { calls.value += 1 }
          .accessibilityAction(named: "Extra") { calls.value += 10 }
        Button("Override") { calls.value += 100 }
          .accessibilityAction { calls.value += 1000 }
          .accessibilityAddTraits(.isSelected)
          .accessibilityRemoveTraits(.isSelected)
      }
    }
    focus.invalidator = loop.scheduler
    loop.scheduler.requestInvalidation(of: [root])
    var frames = 0
    try loop.renderPendingFrames(renderedFrames: &frames)
    let original = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == "Original" })
    let override = try #require(
      loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == "Override" })
    #expect(override.properties?.selected == false)
    #expect(
      loop.handleAccessibilityAction(
        .init(target: try #require(original.actionTarget), action: .activate)) == .accepted)
    #expect(calls.value == 1)
    #expect(
      loop.handleAccessibilityAction(
        .init(target: try #require(original.actionTarget), action: .custom("Extra"))) == .accepted)
    #expect(calls.value == 11)
    #expect(
      loop.handleAccessibilityAction(
        .init(target: try #require(override.actionTarget), action: .activate)) == .accepted)
    #expect(calls.value == 1011)
  }

  @Test func actionsComposeAndRespectCommittedState() throws {
    let root = testIdentity("CustomActions")
    let size = CellSize(width: 40, height: 10)
    let terminal = CursorFocusTestTerminalHost(surfaceSizeProvider: { size })
    let focus = FocusTracker(invalidationIdentities: [root])
    var disabled = false
    var shown = true
    let loop = cursorFocusRunLoop(
      rootIdentity: root, terminal: terminal, terminalSize: size, focusTracker: focus
    ) {
      VStack {
        Text("Custom controls")
        if shown { CustomAccessibilityRating().disabled(disabled) }
      }
    }
    focus.invalidator = loop.scheduler
    var frames = 0
    func render() throws {
      loop.scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &frames)
    }
    func rating() throws -> AccessibilityNode {
      try #require(loop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == "Rating" })
    }
    try render()
    let target = try #require(rating().actionTarget)
    func send(_ action: AccessibilityAction) -> AccessibilityActionResult {
      loop.handleAccessibilityAction(.init(target: target, action: action))
    }
    #expect(try rating().control?.customActions == ["Reset", "Maximum"])
    #expect(try rating().control?.value == .number(2))
    #expect(send(.increment) == .accepted)
    try render()
    #expect(try rating().control?.value == .number(3))
    #expect(try rating().properties?.valueDescription == "3 stars; 1 writes")
    #expect(send(.custom("Reset")) == .accepted)
    try render()
    #expect(try rating().control?.value == .number(0))
    #expect(try rating().properties?.valueDescription == "0 stars; 2 writes")
    #expect(send(.custom("Maximum")) == .accepted)
    try render()
    #expect(try rating().control?.value == .number(5))
    #expect(send(.decrement) == .accepted)
    try render()
    #expect(try rating().control?.value == .number(4))
    #expect(send(.custom("Forged")) == .unsupported)
    #expect(send(.setValue(.number(1))) == .unsupported)
    disabled = true
    try render()
    #expect(send(.increment) == .disabled)
    #expect(send(.custom("Reset")) == .disabled)
    shown = false
    try render()
    #expect(send(.increment) == .staleTarget)
    shown = true
    try render()
    #expect(try rating().actionTarget != target)
    #expect(send(.custom("Reset")) == .staleTarget)
  }
}

private struct CustomAccessibilityRating: View {
  @State private var value = 2
  @State private var writes = 0
  var body: some View {
    Text("Stars: \(value)")
      .accessibilityLabel("Rating")
      .accessibilityValue(Double(value), in: 0...5)
      .accessibilityValue("\(value) stars; \(writes) writes")
      .accessibilityAdjustableAction { direction in
        value = min(5, max(0, value + (direction == .increment ? 1 : -1)))
        writes += 1
      }
      .accessibilityAction(named: "Reset") {
        value = 1
        writes += 100
      }
      .accessibilityAction(named: "Reset") {
        value = 0
        writes += 1
      }
      .accessibilityAction(named: "Maximum") {
        value = 5
        writes += 1
      }
  }
}

@MainActor
private final class AssistiveValueProbe<Value> {
  var value: Value
  var writes: [Value] = []

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      }
    )
  }
}

private struct AssistiveControls: View {
  @State private var enabled = false
  @State private var gain = 2
  @State private var count = 5
  @State private var name = ""
  @State private var secret = ""
  @State private var visible = true
  @State private var modal = false

  var body: some View {
    VStack {
      Toggle("Enabled", isOn: $enabled).id(testIdentity("Toggle"))
      if visible { Slider("Gain", value: $gain, in: 0...10).id(testIdentity("Gain")) }
      Stepper("Count", value: $count, in: 0...10).id(testIdentity("Count"))
      TextField("Name", text: $name).id(testIdentity("Name"))
      TextField("Read only", text: $name)
        .accessibilityProperties(.init(readOnly: true)).id(testIdentity("ReadOnly"))
      SecureField("Secret", text: $secret).id(testIdentity("Secret"))
      Button("Disabled") {}.disabled(true).id(testIdentity("Disabled"))
      Button("Visibility") { visible.toggle() }.id(testIdentity("Visibility"))
      Button("Modal") { modal = true }.id(testIdentity("Modal"))
        .sheet(isPresented: $modal) {
          Button("Close") { modal = false }.id(testIdentity("ModalChild"))
        }
    }
  }
}

private struct PickerConditionalFixture: View {
  @State private var inline = 1
  @State private var menu = 1
  @State private var radio = 1
  @State private var segmented = 1
  @State private var writes = 0
  @State private var secondVisible = true
  @State private var disabled = false

  private func counted(_ value: Binding<Int>) -> Binding<Int> {
    Binding(
      get: { value.wrappedValue },
      set: {
        value.wrappedValue = $0
        writes += 1
      })
  }

  private func choices(_ title: String, value: Binding<Int>, style: AnyPickerStyle) -> some View {
    Picker(title, selection: counted(value)) {
      PickerOption("First", value: 1)
      if secondVisible {
        Text("Visual second").tag(2).accessibilityLabel("Second")
      }
      PickerOption("Unavailable", value: 3).disabled(true)
      PickerOption("Fourth", value: 4)
    }
    .pickerStyle(style)
    .pickerViewportLineCount(3)
    .disabled(disabled)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        choices("Inline mode", value: $inline, style: .inline)
        choices("Menu mode", value: $menu, style: .menu)
        choices("Radio mode", value: $radio, style: .radioGroup)
        choices("Segmented mode", value: $segmented, style: .segmented)
      }
      Text("Picker writes \(writes)")
      Text("Selections \(inline) \(menu) \(radio) \(segmented)")
      Button("Reset choices") {
        inline = 1
        menu = 1
        radio = 1
        segmented = 1
      }
      Button("Toggle second choices") { secondVisible.toggle() }
      Button("Toggle picker availability") { disabled.toggle() }
    }
  }
}
