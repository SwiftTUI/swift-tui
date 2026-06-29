import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextInputRuntimeIntegrationTests {
  @Test("TextField key press dispatch edits around a moved caret")
  func textFieldKeyPressDispatchEditsAroundMovedCaret() {
    final class TextBox {
      var value = "ac"
    }

    let box = TextBox()
    let identity = testIdentity("RuntimeTextField")
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
      TextField(
        "Name",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("b"))))
    #expect(box.value == "abc")
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowRight)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("d"))))
    #expect(box.value == "abcd")
  }

  @Test("SecureField key press dispatch edits text while rendering a masked value")
  func secureFieldKeyPressDispatchEditsWhileMasked() {
    final class SecretBox {
      var value = "ac"
    }

    let box = SecretBox()
    let identity = testIdentity("RuntimeSecureField")
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("b"))))
    #expect(box.value == "abc")

    let artifacts = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("•"))
    #expect(!surface.contains("abc"))
    #expect(!surface.contains("Password"))
  }

  @Test("TextField paste dispatch writes the focused binding once")
  func textFieldPasteDispatchWritesFocusedBindingOnce() throws {
    let box = PasteTextBox()
    let runLoop = makeTextInputRunLoop {
      PasteTextFieldFixture(box: box)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: testIdentity("PasteTextField"))

    runLoop.runLoop.handlePaste(PasteEvent(content: "pasted"))

    #expect(box.value == "pasted")
    #expect(box.setCount == 1)
  }

  @Test("TextField Tab moves focus instead of inserting a tab character")
  func textFieldTabMovesFocusInsteadOfInsertingTab() throws {
    let first = PasteTextBox()
    let second = PasteTextBox()
    first.value = "first"
    second.value = "second"
    let runLoop = makeTextInputRunLoop {
      TabTraversalTextFieldFixture(first: first, second: second)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: testIdentity("TabTraversalTextField", "First"))
    try renderPending(runLoop.runLoop)

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.tab)) == nil)
    try renderPending(runLoop.runLoop)

    #expect(first.value == "first")
    #expect(second.value == "second")
    #expect(!first.value.contains("\t"))
    #expect(!second.value.contains("\t"))
    #expect(
      runLoop.runLoop.focusTracker.currentFocusIdentity
        == testIdentity("TabTraversalTextField", "Second")
    )

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.tab, modifiers: .shift)) == nil)
    try renderPending(runLoop.runLoop)
    #expect(
      runLoop.runLoop.focusTracker.currentFocusIdentity
        == testIdentity("TabTraversalTextField", "First")
    )
    #expect(!first.value.contains("\t"))
    #expect(!second.value.contains("\t"))
  }

  @Test("SecureField paste dispatch writes once and keeps the pasted value masked")
  func secureFieldPasteDispatchWritesOnceAndKeepsValueMasked() throws {
    let box = PasteTextBox()
    let runLoop = makeTextInputRunLoop {
      PasteSecureFieldFixture(box: box)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: testIdentity("PasteSecureField"))

    runLoop.runLoop.handlePaste(PasteEvent(content: "secret"))
    try renderPending(runLoop.runLoop)

    #expect(box.value == "secret")
    #expect(box.setCount == 1)
    #expect(surfaceText(runLoop.host).contains("•"))
    #expect(!surfaceText(runLoop.host).contains("secret"))
    #expect(!surfaceText(runLoop.host).contains("Password"))
  }

  @Test("TextEditor paste dispatch writes once and preserves newlines")
  func textEditorPasteDispatchWritesOnceAndPreservesNewlines() throws {
    let box = PasteTextBox()
    let runLoop = makeTextInputRunLoop {
      PasteTextEditorFixture(box: box)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: testIdentity("PasteTextEditor"))

    runLoop.runLoop.handlePaste(PasteEvent(content: "line 1\nline 2"))

    #expect(box.value == "line 1\nline 2")
    #expect(box.setCount == 1)
  }

  @Test("TextEditor terminal cursor is default and follows moved caret")
  func textEditorTerminalCursorFollowsMovedCaretByDefault() throws {
    let box = PasteTextBox()
    box.value = "abc"
    let identity = testIdentity("DefaultCursorTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 12, height: 4)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)
    try renderPending(runLoop.runLoop)

    let firstCursorPoint = try #require(runLoop.host.movedCursorPoints.last)
    #expect(firstCursorPoint.x > 0)
    #expect(!surfaceText(runLoop.host).contains("abc_"))

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.arrowLeft)) == nil)
    try renderPending(runLoop.runLoop)

    let movedCursorPoint = try #require(runLoop.host.movedCursorPoints.last)
    #expect(movedCursorPoint.x == firstCursorPoint.x - 1)
    #expect(movedCursorPoint.y == firstCursorPoint.y)
    #expect(!surfaceText(runLoop.host).contains("abc_"))
  }

  @Test("TextEditor runtime Ctrl+A selects all before replacement")
  func textEditorRuntimeCtrlASelectsAllBeforeReplacement() throws {
    let box = PasteTextBox()
    box.value = "hello"
    let identity = testIdentity("SelectAllTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 20, height: 5)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl)) == nil)
    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.character("Z"))) == nil)
    #expect(box.value == "Z")
  }

  @Test("TextEditor runtime Ctrl+C copies the selection without exiting")
  func textEditorRuntimeCtrlCCopiesSelectionWithoutExiting() throws {
    let box = PasteTextBox()
    box.value = "hello"
    let identity = testIdentity("CopyTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 20, height: 5)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl)) == nil)
    let reason = runLoop.runLoop.handleKeyPress(KeyPress(.character("c"), modifiers: .ctrl))

    #expect(reason == nil)
    #expect(runLoop.host.clipboardWrites == ["hello"])
    #expect(box.value == "hello")
  }

  @Test("TextEditor runtime Ctrl+X cuts the selection after copying")
  func textEditorRuntimeCtrlXCutsSelectionAfterCopying() throws {
    let box = PasteTextBox()
    box.value = "hello"
    let identity = testIdentity("CutTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 20, height: 5)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl)) == nil)
    let reason = runLoop.runLoop.handleKeyPress(KeyPress(.character("x"), modifiers: .ctrl))

    #expect(reason == nil)
    #expect(runLoop.host.clipboardWrites == ["hello"])
    #expect(box.value == "")
  }

  @Test("TextEditor runtime Ctrl+V pastes host clipboard text")
  func textEditorRuntimeCtrlVPastesHostClipboardText() throws {
    let box = PasteTextBox()
    box.value = "hello "
    let identity = testIdentity("PasteShortcutTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 20, height: 5)
    }
    runLoop.host.clipboardReadText = "world"

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    let reason = runLoop.runLoop.handleKeyPress(KeyPress(.character("v"), modifiers: .ctrl))

    #expect(reason == nil)
    #expect(box.value == "hello world")
    #expect(runLoop.host.clipboardReadCount == 1)
  }

  @Test("SecureField runtime Ctrl+C and Ctrl+X do not expose secure text")
  func secureFieldRuntimeClipboardShortcutsDoNotExposeSecureText() throws {
    let box = PasteTextBox()
    box.value = "secret"
    let identity = testIdentity("ClipboardSecureField")
    let runLoop = makeTextInputRunLoop {
      SecureField("Password", text: box.binding())
        .id(identity)
        .textFieldStyle(.plain)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    #expect(runLoop.runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl)) == nil)
    _ = runLoop.runLoop.handleKeyPress(KeyPress(.character("c"), modifiers: .ctrl))
    _ = runLoop.runLoop.handleKeyPress(KeyPress(.character("x"), modifiers: .ctrl))

    #expect(runLoop.host.clipboardWrites.isEmpty)
    #expect(box.value == "secret")
  }

  @Test("TextEditor runtime Ctrl+D uses default exit binding")
  func textEditorRuntimeCtrlDUsesDefaultExitBinding() throws {
    let box = PasteTextBox()
    box.value = "hello"
    let identity = testIdentity("ExitBindingTextEditor")
    let exitKey = KeyPress(.character("d"), modifiers: .ctrl)
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 20, height: 5)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    let reason = runLoop.runLoop.handleKeyPress(exitKey)

    #expect(reason == .userExit(exitKey))
    #expect(box.value == "hello")
  }

  @Test("TextEditor runtime scrolls to keep the caret visible")
  func textEditorRuntimeScrollsToKeepCaretVisible() throws {
    let box = PasteTextBox()
    box.value = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
    let identity = testIdentity("CaretVisibleTextEditor")
    let runLoop = makeTextInputRunLoop {
      TextEditor(text: box.binding())
        .id(identity)
        .frame(width: 18, height: 5)
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)
    try renderPending(runLoop.runLoop)

    let surface = surfaceText(runLoop.host)
    #expect(!surface.contains("Line 1"))
    #expect(surface.contains("Line 6"))
  }

  @Test("Paste falls back to scalar key presses for non-text focused handlers")
  func pasteFallsBackToScalarKeyPressesForNonTextHandlers() throws {
    final class Recorder {
      var keys: [KeyEvent] = []
    }

    let recorder = Recorder()
    let identity = testIdentity("PasteKeyFallback")
    let runLoop = makeTextInputRunLoop {
      Text("Target")
        .id(identity)
        .focusable(true)
        .onKeyPress(.any) { keyPress in
          recorder.keys.append(keyPress.key)
          return .handled
        }
    }

    try renderInitial(runLoop.runLoop)
    _ = runLoop.runLoop.focusTracker.setFocus(to: identity)

    runLoop.runLoop.handlePaste(PasteEvent(content: "a b"))

    #expect(recorder.keys == [.character("a"), .space, .character("b")])
  }
}

@MainActor
private final class PasteTextBox {
  var value = ""
  var setCount = 0

  func binding() -> Binding<String> {
    Binding(
      get: { self.value },
      set: { value in
        self.value = value
        self.setCount += 1
      }
    )
  }
}

@MainActor
private struct PasteTextFieldFixture: View {
  let box: PasteTextBox

  var body: some View {
    TextField("Name", text: box.binding())
      .id(testIdentity("PasteTextField"))
      .textFieldStyle(.plain)
  }
}

@MainActor
private struct TabTraversalTextFieldFixture: View {
  let first: PasteTextBox
  let second: PasteTextBox

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("First", text: first.binding())
        .id(testIdentity("TabTraversalTextField", "First"))
        .textFieldStyle(.plain)
      TextField("Second", text: second.binding())
        .id(testIdentity("TabTraversalTextField", "Second"))
        .textFieldStyle(.plain)
    }
  }
}

@MainActor
private struct PasteSecureFieldFixture: View {
  let box: PasteTextBox

  var body: some View {
    SecureField("Password", text: box.binding())
      .id(testIdentity("PasteSecureField"))
      .textFieldStyle(.plain)
  }
}

@MainActor
private struct PasteTextEditorFixture: View {
  let box: PasteTextBox

  var body: some View {
    TextEditor(text: box.binding())
      .id(testIdentity("PasteTextEditor"))
      .frame(width: 20, height: 5)
  }
}

@MainActor
private func makeTextInputRunLoop<V: View>(
  @ViewBuilder content: @escaping () -> V
) -> (runLoop: RunLoop<Int, V>, host: TextInputRuntimeTerminalHost) {
  let terminalSize = CellSize(width: 40, height: 8)
  let host = TextInputRuntimeTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("TextInputRuntimeRoot")
  var environmentValues = EnvironmentValues()
  environmentValues.terminalAppearance = host.appearance
  environmentValues.terminalSize = terminalSize
  let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: TextInputRuntimeInputReader(),
    signalReader: TextInputRuntimeSignalReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: focusTracker,
    environmentValues: environmentValues,
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  focusTracker.invalidator = runLoop.scheduler
  return (runLoop, host)
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

@MainActor
private func renderPending<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func surfaceText(_ host: TextInputRuntimeTerminalHost) -> String {
  host.latestSurface?.lines.joined(separator: "\n") ?? ""
}

private final class TextInputRuntimeTerminalHost: PresentationSurface,
  ClipboardWritingPresentationSurface, ClipboardReadingPresentationSurface,
  TerminalCursorFocusPresentationSurface
{
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private(set) var clipboardWrites: [String] = []
  var clipboardReadText: String?
  private(set) var clipboardReadCount = 0
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
  @MainActor
  func writeClipboard(_ text: String) throws -> Bool {
    clipboardWrites.append(text)
    return true
  }

  @MainActor
  func readClipboard() throws -> String? {
    clipboardReadCount += 1
    return clipboardReadText
  }

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

extension TextInputRuntimeTerminalHost: DamageAwarePresentationSurface {
  func present(_ surface: RasterSurface, damage _: PresentationDamage?) throws
    -> TerminalPresentationMetrics
  {
    try present(surface)
  }
}

private final class TextInputRuntimeInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class TextInputRuntimeSignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
