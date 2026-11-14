import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A host input method's full-state edits through the real run loop: the
/// accessibility action route the Android `swift_tui_android_text_input`
/// ingress uses, the controls' retained editing state, and the frame's
/// published text and UTF-16 selection that the host mirrors.
@MainActor
@Suite
struct TextInputCompositionRuntimeTests {
  @Test(
    "CJK candidate composition updates, replaces and commits once, mid-string",
    arguments: [false, true])
  func candidateComposition(editor: Bool) throws {
    let scene = try Scene(editor: editor, text: "前后")
    defer { scene.shutdown() }
    try scene.focus()
    // Caret between the two characters, then pinyin pre-edit text.
    #expect(try scene.edit("前n后", caret: 2, composing: 1..<2) == .accepted)
    #expect(try scene.edit("前ni后", caret: 3, composing: 1..<3) == .accepted)
    #expect(try scene.edit("前nihao后", caret: 6, composing: 1..<6) == .accepted)
    try scene.render()
    #expect(scene.text == "前nihao后")
    // The pre-edit text is drawn marked; its neighbours are not.
    #expect(scene.markedText == "nihao")
    #expect(try scene.publishedSelection() == 6..<6)
    let writesWhileComposing = scene.writes
    #expect(writesWhileComposing == 3)

    // The candidate replaces exactly the marked range.
    #expect(try scene.edit("前你好后", caret: 3, composing: nil) == .accepted)
    try scene.render()
    #expect(scene.text == "前你好后")
    #expect(scene.writes == writesWhileComposing + 1)
    #expect(scene.markedText == "")
    #expect(try scene.publishedSelection() == 3..<3)

    // Repeating the committed state inserts nothing and writes nothing.
    #expect(try scene.edit("前你好后", caret: 3, composing: nil) == .accepted)
    #expect(scene.writes == writesWhileComposing + 1)

    // The caret the host placed is the caret ordinary keys use.
    _ = scene.runLoop.handle(.input(.key(.init(.character("!")))))
    try scene.render()
    #expect(scene.text == "前你好!后")
  }

  @Test("finishing a composition as it stands commits once without rewriting the text")
  func commitAsIs() throws {
    let scene = try Scene(editor: false, text: "")
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("hel", caret: 3, composing: 0..<3) == .accepted)
    #expect(try scene.edit("hello", caret: 5, composing: 0..<5) == .accepted)
    let writes = scene.writes
    #expect(try scene.edit("hello", caret: 5, composing: nil) == .accepted)
    try scene.render()
    #expect(scene.text == "hello" && scene.writes == writes)
    #expect(scene.markedText == "")
  }

  @Test("cancelling restores the pre-composition text and caret")
  func cancellation() throws {
    let scene = try Scene(editor: false, text: "ab")
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("ab", caret: 1, composing: nil) == .accepted)
    try scene.render()
    let writes = scene.writes
    #expect(try scene.edit("anib", caret: 3, composing: 1..<3) == .accepted)
    try scene.render()
    #expect(scene.text == "anib" && scene.markedText == "ni")
    // The input method empties its pre-edit text.
    #expect(try scene.edit("ab", caret: 1, composing: nil) == .accepted)
    try scene.render()
    #expect(scene.text == "ab" && scene.writes == writes + 2)
    #expect(scene.markedText == "")
    #expect(try scene.publishedSelection() == 1..<1)
  }

  @Test("combining marks and supplementary-plane emoji translate by grapheme, not code unit")
  func graphemeTranslation() throws {
    let scene = try Scene(editor: false, text: "")
    defer { scene.shutdown() }
    try scene.focus()
    // A dead-key acute composed after "e": the marked code unit is the
    // combining mark alone (UTF-16 1..<2), inside the grapheme "é".
    #expect(try scene.edit("e\u{301}x", caret: 2, composing: 1..<2) == .accepted)
    try scene.render()
    #expect(scene.markedText == "e\u{301}")
    #expect(try scene.publishedSelection() == 2..<2)

    // An emoji pair composed after it: UTF-16 3..<5 is one Character.
    #expect(try scene.edit("e\u{301}x😀z", caret: 5, composing: 3..<5) == .accepted)
    try scene.render()
    #expect(scene.markedText == "😀")
    #expect(try scene.publishedSelection() == 5..<5)

    // A caret reported between the surrogates snaps to the end of the pair,
    // and a marked range that splits it covers the whole emoji.
    #expect(try scene.edit("e\u{301}x😀z", caret: 4, composing: 4..<5) == .accepted)
    try scene.render()
    #expect(scene.markedText == "😀")
    #expect(try scene.publishedSelection() == 5..<5)

    // A joined emoji replaces the marked emoji; the suffix is untouched.
    #expect(try scene.edit("e\u{301}x👩🏽‍💻z", caret: 10, composing: nil) == .accepted)
    try scene.render()
    #expect(scene.text == "e\u{301}x👩🏽‍💻z")
    #expect(try scene.publishedSelection() == 10..<10)
    _ = scene.runLoop.handle(.input(.key(.backspace)))
    try scene.render()
    #expect(scene.text == "e\u{301}xz")

    // Offsets outside the text reject the whole edit and change nothing.
    let writes = scene.writes
    for (caret, composing) in [(99, nil), (0, 0..<99), (-2, nil)] as [(Int, Range<Int>?)] {
      #expect(try scene.edit("abc", caret: caret, composing: composing) == .invalidValue)
    }
    #expect(scene.text == "e\u{301}xz" && scene.writes == writes)
  }

  @Test("selection movement by the input method is applied without writing the binding")
  func selectionMovement() throws {
    let scene = try Scene(editor: false, text: "hello world")
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("hello world", anchor: 5, head: 5, composing: nil) == .accepted)
    try scene.render()
    #expect(try scene.publishedSelection() == 5..<5)
    // A directed selection, head before anchor.
    #expect(try scene.edit("hello world", anchor: 5, head: 0, composing: nil) == .accepted)
    try scene.render()
    let input = try #require(try scene.node().textInput)
    #expect(input.selection == 0..<5 && input.insertionOffset == 0)
    // Marking existing text (setComposingRegion) changes no text either.
    #expect(try scene.edit("hello world", anchor: 5, head: 5, composing: 0..<5) == .accepted)
    try scene.render()
    #expect(scene.markedText == "hello")
    #expect(scene.writes == 0)
    // Replacing that marked word keeps the suffix and puts the caret after it.
    #expect(try scene.edit("HELLO world", anchor: 5, head: 5, composing: nil) == .accepted)
    try scene.render()
    #expect(scene.text == "HELLO world" && scene.writes == 1)
    #expect(try scene.publishedSelection() == 5..<5)
  }

  @Test("runtime keys, paste and submit commit a composition before they apply")
  func runtimeInputCommits() throws {
    var submitted: [String] = []
    let scene = try Scene(editor: false, text: "", onSubmit: { submitted.append($0) })
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("ni", caret: 2, composing: 0..<2) == .accepted)
    _ = scene.runLoop.handle(.input(.key(.arrowLeft)))
    try scene.render()
    #expect(scene.text == "ni" && scene.markedText == "")
    #expect(try scene.publishedSelection() == 1..<1)

    #expect(try scene.edit("nihao", caret: 5, composing: 0..<5) == .accepted)
    _ = scene.runLoop.handle(.input(.paste(.init(content: "!"))))
    try scene.render()
    #expect(scene.text == "nihao!" && scene.markedText == "")

    #expect(try scene.edit("nihao!ma", caret: 8, composing: 6..<8) == .accepted)
    _ = scene.runLoop.handle(.input(.key(.return)))
    try scene.render()
    #expect(submitted == ["nihao!ma"])
    #expect(scene.text == "nihao!ma" && scene.markedText == "")
  }

  @Test("an application rewrite of the bound text commits what the binding holds")
  func applicationRewrite() throws {
    let scene = try Scene(editor: false, text: "")
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("ni", caret: 2, composing: 0..<2) == .accepted)
    try scene.render()
    #expect(scene.markedText == "ni")
    scene.box.text = "cleared by the app"
    try scene.renderAfterExternalMutation()
    #expect(try scene.node().control?.value == .text("cleared by the app"))
    // The retained value restarts from the binding: no stale mark is drawn.
    #expect(scene.markedText == "")
    #expect(try scene.publishedSelection() == 18..<18)
  }

  @Test("focus loss and a control switch commit the composition")
  func focusLossCommits() throws {
    let scene = try Scene(editor: false, text: "", second: true)
    defer { scene.shutdown() }
    try scene.focus()
    #expect(try scene.edit("ni", caret: 2, composing: 0..<2) == .accepted)
    try scene.render()
    #expect(scene.runLoop.textCompositionIdentity != nil)
    #expect(scene.markedText == "ni")
    let writes = scene.writes

    // Tab moves keyboard focus to the second field.
    _ = scene.runLoop.handle(.input(.key(.tab)))
    try scene.render()
    #expect(scene.runLoop.textCompositionIdentity == nil)
    #expect(scene.markedText == "")
    #expect(scene.text == "ni" && scene.writes == writes)

    // Returning focus shows committed text, with no mark.
    _ = scene.runLoop.handle(.input(.key(.tab, modifiers: .shift)))
    try scene.render()
    #expect(scene.markedText == "")

    // An edit queued for the first field while the second holds focus is
    // applied (the target is live) but cannot leave a mark behind.
    _ = scene.runLoop.handle(.input(.key(.tab)))
    try scene.render()
    #expect(
      scene.runLoop.handle(
        .input(
          .accessibility(
            .init(
              target: try #require(try scene.node().actionTarget),
              action: .editText(
                .init(
                  text: "nih", anchor: 3, head: 3, inputMethod: .init(composition: 0..<3))),
              requestID: 7)))) == nil)
    try scene.render()
    #expect(scene.text == "nih" && scene.markedText == "")
    #expect(scene.runLoop.textCompositionIdentity == nil)
    #expect(scene.runLoop.latestAccessibilityActionResponse?.requestID == 7)
    #expect(scene.runLoop.latestAccessibilityActionResponse?.result == .accepted)
  }

  @Test("secure, read-only, disabled and single-line newline edits are refused whole")
  func refusals() throws {
    var secret = "hunter2"
    var writes = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompositionRefusals"), size: .init(width: 40, height: 10)
    ) {
      VStack {
        SecureField(
          "Secret",
          text: Binding(
            get: { secret },
            set: {
              secret = $0
              writes += 1
            }))
        TextField("Locked", text: .constant("locked")).accessibilityProperties(
          .init(readOnly: true))
        TextField("Off", text: .constant("off")).disabled(true)
        TextField("Line", text: .constant("line"))
      }
    }
    defer { harness.shutdown() }
    func send(_ label: String, _ text: String) throws -> AccessibilityActionResult {
      let target = try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label && $0.control != nil
        }?.actionTarget)
      return harness.runLoop.handleAccessibilityAction(
        .init(
          target: target,
          action: .editText(
            .init(text: text, anchor: 0, head: 0, inputMethod: .init(composition: nil)))))
    }
    // The runtime never published the secret, so no host could mirror it.
    #expect(try send("Secret", "x") == .unsupported)
    #expect(secret == "hunter2" && writes == 0)
    #expect(try send("Locked", "x") == .unsupported)
    #expect(try send("Off", "x") == .disabled)
    #expect(try send("Line", "a\nb") == .invalidValue)
    #expect(harness.runLoop.textCompositionIdentity == nil)
  }

  @Test("the input-method record parses losslessly and rejects malformed forms")
  func wire() {
    let parsed = TextInputEditWire.parseCommand(
      "textInput:42:field%3A1:%E5%89%8Dni%E5%90%8E:3:3:1:3")
    #expect(
      parsed
        == .init(
          target: "field:1",
          action: .editText(
            .init(text: "前ni后", anchor: 3, head: 3, inputMethod: .init(composition: 1..<3))),
          requestID: 42))
    let committed = TextInputEditWire.parseCommand("textInput:1:t::0:0:-1:-1")
    #expect(
      committed?.action
        == .editText(.init(text: "", anchor: 0, head: 0, inputMethod: .init(composition: nil))))
    // An input-method edit is never equal to an assistive replacement.
    #expect(committed?.action != .editText(.init(text: "", anchor: 0, head: 0)))
    for input in [
      "textInput:1:t:a:0:0:-1:0", "textInput:1:t:a:0:0:0:-1", "textInput:1:t:a:0:0:2:1",
      "textInput:1:t:a:-1:0:-1:-1", "textInput:1:t:a:+1:0:-1:-1", "textInput:1:t:a:0:0",
      "textInput::t:a:0:0:-1:-1", "textInput:x:t:a:0:0:-1:-1", "textInput:1::a:0:0:-1:-1",
      "textInput:1:t:%FF:0:0:-1:-1", "textInput:1:t:a:0:0:-1:-1:extra",
      "accessibility:1:t:editText:text:a:0:0", "textInput:1:t:a:٣:0:-1:-1",
      "textInput:1:t:a:99999999999:0:-1:-1",
    ] {
      #expect(TextInputEditWire.parseCommand(input) == nil, "\(input)")
    }
  }
}

@MainActor
private final class CompositionTextBox {
  var text: String
  var second = ""
  var writes = 0
  init(_ text: String) { self.text = text }
}

/// One text control under a real run loop. The recording surface keeps the
/// last raster, so a test reads marked text the way a host draws it: from the
/// underlined cells.
@MainActor
private struct Scene {
  let runLoop: SwiftTUIRuntime.RunLoop<Int, AnyView>
  let box: CompositionTextBox
  private let surface: CompositionRecordingSurface
  private let rootIdentity: Identity

  init(
    editor: Bool, text: String, second: Bool = false,
    onSubmit: (@MainActor (String) -> Void)? = nil
  ) throws {
    let box = CompositionTextBox(text)
    let binding = Binding(
      get: { box.text },
      set: {
        box.text = $0
        box.writes += 1
      })
    let rootIdentity = testIdentity("TextComposition")
    let size = CellSize(width: 40, height: 12)
    let surface = CompositionRecordingSurface(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    // AnyView policy: test-only erasure so one run loop type serves the
    // field, editor and two-field scenes.
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      inputReader: CompositionEmptyKeyReader(),
      signalReader: CompositionEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in
        AnyView(
          VStack(alignment: .leading) {
            if editor {
              TextEditor(text: binding).accessibilityLabel("Editor").frame(width: 30, height: 4)
            } else {
              TextField("Editor", text: binding).onSubmit { onSubmit?(box.text) }
            }
            if second {
              TextField("Second", text: Binding(get: { box.second }, set: { box.second = $0 }))
            }
          })
      }
    )
    focusTracker.invalidator = scheduler
    self.box = box
    self.surface = surface
    self.rootIdentity = rootIdentity
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
    runLoop.renderer.enableSelectiveEvaluation()
  }

  var text: String { box.text }
  var writes: Int { box.writes }

  func shutdown() { runLoop.lifecycleCoordinator.shutdown() }

  func render() throws {
    var frames = 0
    try runLoop.renderPendingFrames(renderedFrames: &frames)
  }

  func renderAfterExternalMutation() throws {
    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    try render()
  }

  func node() throws -> AccessibilityNode {
    try #require(
      runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Editor" && $0.control != nil
      })
  }

  func focus() throws {
    let result = runLoop.handleAccessibilityAction(
      .init(target: try #require(try node().actionTarget), action: .focus))
    #expect(result == .accepted)
    try render()
  }

  func edit(_ text: String, caret: Int, composing: Range<Int>?) throws
    -> AccessibilityActionResult
  {
    try edit(text, anchor: caret, head: caret, composing: composing)
  }

  /// Offsets are UTF-16 code units, as a host sends them.
  func edit(_ text: String, anchor: Int, head: Int, composing: Range<Int>?) throws
    -> AccessibilityActionResult
  {
    runLoop.handleAccessibilityAction(
      .init(
        target: try #require(try node().actionTarget),
        action: .editText(
          .init(
            text: text, anchor: anchor, head: head,
            inputMethod: .init(composition: composing)))))
  }

  /// The selection the frame publishes to hosts, in UTF-16 code units.
  func publishedSelection() throws -> Range<Int> {
    try #require(try node().textInput).selection
  }

  /// The characters the last presented frame draws underlined, in reading
  /// order. No built-in field chrome underlines, so this is the marked text.
  var markedText: String {
    guard let raster = surface.lastSurface else { return "" }
    var marked = ""
    for row in raster.cells {
      for cell in row where cell.continuationLeadX == nil {
        if cell.style?.underlineStyle != nil { marked.append(cell.character) }
      }
    }
    return marked
  }
}

private final class CompositionRecordingSurface: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  let pointerInputCapabilities: PointerInputCapabilities = .cellOnly
  private(set) var lastSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_: String) throws {}
}

private final class CompositionEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class CompositionEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
