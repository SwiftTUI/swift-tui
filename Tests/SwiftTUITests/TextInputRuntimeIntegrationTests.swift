import Testing

@_spi(Runners) @testable import SwiftTUI
@testable import SwiftTUICore
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

private final class TextInputRuntimeTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
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
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

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
