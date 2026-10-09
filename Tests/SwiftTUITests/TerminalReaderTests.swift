import Foundation
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TerminalReaderTests {
  @Test("unnamed layout wrappers do not create stops and descendants retain meaningful hierarchy")
  func layoutWrappers() {
    var model = TerminalReaderModel()
    let heading = node("Section", role: .heading(level: 1))
    var wrapper = node("Layout", parent: "Section")
    wrapper.label = nil
    let control = node("Save", parent: "Layout", role: .button)
    _ = model.update(frame(1, [heading, wrapper, control]))
    #expect(model.chunks.count == 2)
    #expect(model.hierarchy(up: false).contains("Save"))
    #expect(model.hierarchy(up: true).contains("Section"))
  }
  @Test("duplicate reported identities remain separately readable and dispatch their own tokens")
  func duplicateIdentities() throws {
    var commands = TerminalReaderCommands()
    var first = node("Duplicate", role: .button)
    first.label = "First occurrence"
    first.actionTarget = "first#1"
    first.control = .init(actions: [.activate])
    var second = first
    second.label = "Second occurrence"
    second.actionTarget = "second#1"
    _ = commands.model.update(frame(1, [first, second]))
    #expect(commands.command("read").output.contains("First occurrence"))
    #expect(commands.command("next").output.contains("Second occurrence"))
    #expect(commands.command("activate").request?.target == "second#1")
    first.label = "Changed first"
    _ = commands.model.update(frame(2, [first, second]))
    #expect(commands.command("read").output.contains("Current 2 of 2. button. Second occurrence"))
    #expect(commands.command("previous").output.contains("Changed first"))
  }
  private func node(_ name: String, parent: String? = nil, role: AccessibilityRole = .group)
    -> AccessibilityNode
  {
    .init(
      identity: testIdentity(name), parentIdentity: parent.map { testIdentity($0) },
      rect: .init(origin: .zero, size: .init(width: 20, height: 1)), role: role, label: name)
  }
  private func frame(
    _ sequence: UInt64, _ nodes: [AccessibilityNode],
    announcements: [AccessibilityAnnouncement] = []
  ) -> SemanticHostFrame {
    .init(
      sequence: sequence, raster: .init(size: .init(width: 20, height: 4), lines: []),
      semantics: .init(accessibilityNodes: nodes, accessibilityAnnouncements: announcements),
      focusedIdentity: nil)
  }

  @Test("semantic review remains stable across repaint, updates, removals and bounded history")
  func review() {
    var reader = TerminalReaderCommands()
    let parent = node("Document", role: .heading(level: 1))
    var child = node("Paragraph", parent: "Document")
    child.label = "let retries = 3\nprint(retries)"
    _ = reader.model.update(frame(1, [parent, child]))
    #expect(reader.command("down").output.contains("print(retries)"))
    let history = reader.model.history
    child.label = "Changed"
    _ = reader.model.update(frame(2, [parent, child]))
    #expect(reader.model.currentChunk?.node.identity == child.identity)
    #expect(reader.model.history == history)
    #expect(reader.command("updates").output.contains("Changed"))
    #expect(reader.command("updates").output == "No pending updates.")
    _ = reader.model.update(frame(3, [parent, child]))
    #expect(reader.command("updates").output == "No pending updates.")
    #expect(reader.command("up").output.contains("Document"))
    #expect(reader.command("find Changed").output.contains("Changed"))
    #expect(reader.model.update(frame(4, [parent])).joined().contains("removed"))
    #expect(reader.model.currentChunk?.node.identity == parent.identity)
    for _ in 0..<150 { _ = reader.command("read") }
    #expect(reader.model.history.count == 128 && reader.model.historyEvicted)
  }

  @Test("hidden ancestors and modal scopes exclude background reading and restore review")
  func scope() {
    var model = TerminalReaderModel()
    let background = node("Background", role: .button)
    var hidden = node("Hidden")
    hidden.hidden = true
    let secret = node("Hidden descendant", parent: "Hidden")
    _ = model.update(frame(1, [background, hidden, secret]))
    #expect(model.chunks.map(\.node.identity) == [background.identity])
    var modal = node("Dialog", role: .sheet)
    modal.properties = .init(modal: true)
    let action = node("Close", parent: "Dialog", role: .button)
    _ = model.update(frame(2, [background, modal, action]))
    #expect(model.chunks.map(\.node.identity) == [modal.identity, action.identity])
    #expect(model.currentChunk?.node.identity == modal.identity)
    _ = model.update(frame(3, [background]))
    #expect(model.currentChunk?.node.identity == background.identity)
  }

  @Test("progress is coalesced while repeated and concurrent announcements retain order")
  func updates() {
    var model = TerminalReaderModel()
    var progress = node("Upload", role: .progressBar)
    progress.control = .init(actions: [], value: .number(0), minimum: 0, maximum: 3)
    _ = model.update(frame(1, [progress]))
    for index in 1...3 {
      progress.control = .init(actions: [], value: .number(Double(index)), minimum: 0, maximum: 3)
      _ = model.update(
        frame(
          UInt64(index + 1), [progress],
          announcements: [
            .init(message: "Saved 😀"), .init(message: "Check error", politeness: .assertive),
          ]))
    }
    let output = model.takeUpdates().joined(separator: "\n")
    #expect(output.components(separatedBy: "Saved 😀").count == 4)
    #expect(output.components(separatedBy: "Check error").count == 4)
    #expect(!output.contains("progressBar. Upload. 1.0"))
    #expect(output.contains("progressBar. Upload. 3.0"))
    #expect(model.history.isEmpty)
  }

  @Test(
    "nested dialogs restore each independent review position and hidden dialogs do not trap review")
  func nestedScopes() {
    var model = TerminalReaderModel()
    let background = node("Background")
    var dialog = node("Dialog")
    dialog.properties = .init(modal: true)
    let action = node("Action", parent: "Dialog")
    var nested = node("Nested", parent: "Dialog")
    nested.properties = .init(modal: true)
    _ = model.update(frame(1, [background]))
    _ = model.update(frame(2, [background, dialog, action]))
    model.current = model.chunks.first { $0.node.identity == action.identity }?.id
    _ = model.update(frame(3, [background, dialog, action, nested]))
    #expect(model.currentChunk?.node.identity == nested.identity)
    _ = model.update(frame(4, [background, dialog, action]))
    #expect(model.currentChunk?.node.identity == action.identity)
    _ = model.update(frame(5, [background]))
    #expect(model.currentChunk?.node.identity == background.identity)
    dialog.hidden = true
    _ = model.update(frame(6, [background, dialog, nested]))
    #expect(model.chunks.map(\.node.identity) == [background.identity])
  }

  @Test("scene review uses the existing scene input and primary output without restarting state")
  func scenes() async throws {
    let primaryHost = ReaderRecordingHost()
    let secondaryHost = ReaderRecordingHost()
    let primary = TerminalReaderSurface(terminal: primaryHost, enabled: true)
    let secondary = TerminalReaderSurface(terminal: secondaryHost, enabled: true)
    func endpoint(_ id: String, _ surface: TerminalReaderSurface) -> SharedSceneEndpoint {
      .init(
        descriptor: .init(id: .init(id), title: id, isDefault: id == "primary"),
        resources: .init(presentationSurface: surface, terminalInputReader: ReaderEmptyInput()),
        isPrimary: false)
    }
    let a = endpoint("primary", primary)
    let b = endpoint("secondary", secondary)
    defer {
      a.stop()
      b.stop()
    }
    let hub = TerminalReaderSceneHub(endpoints: [a, b])
    let input = TerminalReaderInput(source: ReaderEmptyInput(), surface: primary)
    input.sceneHub = hub
    var button = node("Secondary action", role: .button)
    button.actionTarget = "secondary#1"
    button.control = .init(actions: [.activate])
    try a.surface.present(frame(1, [node("Primary content")]))
    try b.surface.present(frame(1, [button]))
    #expect(primaryHost.output.isEmpty && secondaryHost.output.isEmpty)
    for char in "scene secondary" { _ = try input.process(.key(.character(char))) }
    _ = try input.process(.key(.return))
    #expect(primaryHost.output.contains("Secondary action"))
    for char in "activate" { _ = try input.process(.key(.character(char))) }
    #expect(try input.process(.key(.return)).events.isEmpty)
    var events = b.input.scopedInputEvents().makeAsyncIterator()
    let event = await events.next()
    if case .accessibility(let request) = event?.event {
      #expect(request.target == "secondary#1")
      b.surface.receiveReaderResponse(
        .init(requestID: request.requestID!, target: request.target, result: .accepted))
    } else {
      Issue.record("Reader did not route to the retained secondary scene")
    }
    try b.surface.present(frame(2, [button]))
    #expect(primaryHost.output.contains("Action accepted"))
    #expect(secondaryHost.output.isEmpty)
    #expect(
      try InputDispatchContext.$origin.withValue(.terminal) {
        try b.surface.writeClipboard("review")
      })
    #expect(primaryHost.copied == "review" && secondaryHost.copied == nil)
    hub.reset()
    #expect(hub.selectedSurface === primary)
    #expect(secondary.commands.model.currentChunk?.node.identity == button.identity)
  }

  @Test("long Unicode reading is paged and control sequences never reach the terminal")
  func text() {
    var model = TerminalReaderModel()
    var text = node("Prose")
    text.label = String(repeating: "a", count: 9000) + "😀 last\u{1b}[2J\u{009d}bad\u{202e}"
    _ = model.update(frame(1, [text]))
    #expect(model.read().contains("truncated"))
    #expect(model.textPage(from: 9000).contains("😀 last"))
    #expect(
      !model.textPage(from: 9000).unicodeScalars.contains {
        $0.value == 27 || $0.value == 0x9d || $0.value == 0x202e
      })
    #expect(model.find("😀 last").contains("Current 1"))
  }

  @Test("role and authored category navigation shares scope and progress announces only completion")
  func categoriesAndQuietProgress() {
    var model = TerminalReaderModel()
    model.announcesUpdates = true
    let heading = node("Introduction", role: .heading(level: 1))
    var chart = node("Chart")
    chart.navigationCategories = ["Data"]
    var progress = node("Upload", role: .progressBar)
    progress.control = .init(actions: [], value: .number(0), minimum: 0, maximum: 2)
    _ = model.update(frame(1, [heading, chart, progress]))
    #expect(model.category("Data").contains("Chart"))
    #expect(model.category("Headings").contains("Introduction"))
    progress.control = .init(actions: [], value: .number(1), minimum: 0, maximum: 2)
    #expect(model.update(frame(2, [heading, chart, progress])).isEmpty)
    progress.control = .init(actions: [], value: .number(2), minimum: 0, maximum: 2)
    #expect(model.update(frame(3, [heading, chart, progress])).joined().contains("2.0"))
  }

  @Test("oversized pasted commands are discarded as a whole and a subsequent command works")
  func inputBound() throws {
    let terminal = ReaderRecordingHost()
    let surface = TerminalReaderSurface(terminal: terminal, enabled: true)
    let input = TerminalReaderInput(source: ReaderEmptyInput(), surface: surface)
    try surface.present(frame(1, [node("Content")]))
    _ = try input.process(.paste(.init(content: String(repeating: "x", count: 65_537))))
    #expect(try input.process(.key(.return)).events.isEmpty)
    #expect(terminal.output.contains("was discarded"))
    _ = try input.process(.paste(.init(content: "read")))
    _ = try input.process(.key(.return))
    #expect(terminal.output.hasSuffix("Content\r\nCommand: "))
  }

  @Test("selection uses opaque option IDs and disabled actions do not issue requests")
  func actions() throws {
    var commands = TerminalReaderCommands()
    var picker = node("Choice", role: .picker)
    picker.actionTarget = "issued#1"
    picker.control = .init(
      actions: [.setValue], value: .text("opaque-a"),
      selection:
        .init(
          presentation: .menu,
          options: [
            .init(id: "opaque-a", label: "First", isEnabled: false),
            .init(id: "opaque-b", label: "Second", isEnabled: true),
          ]))
    _ = commands.model.update(frame(1, [picker]))
    #expect(commands.command("read").output.contains("First"))
    #expect(!commands.command("read").output.contains("opaque-a"))
    #expect(commands.command("choose 1").request == nil)
    let request = try #require(commands.command("choose 2").request)
    #expect(request.action == .setValue(.text("opaque-b")))
    #expect(commands.command("choose 2").request == nil)
    #expect(
      commands.acknowledge(
        .init(requestID: request.requestID!, target: request.target, result: .accepted)) != nil)
    picker.isEnabled = false
    _ = commands.model.update(frame(2, [picker]))
    #expect(commands.command("choose 2").request == nil)
  }

  @Test("editing preserves graphemes and rejects a draft after application text changes")
  func editing() throws {
    var commands = TerminalReaderCommands()
    var field = node("Editor", role: .textEditor)
    field.actionTarget = "editor#1"
    field.control = .init(actions: [.editText, .selectText], value: .text("a😀bc"))
    _ = commands.model.update(frame(1, [field]))
    _ = commands.command("edit")
    _ = commands.command("select 1 2")
    _ = commands.command("insert é")
    _ = commands.command("append-line next")
    let request = try #require(commands.command("save").request)
    #expect(request.action == .editText(.init(text: "aébc\nnext", anchor: 9, head: 9)))
    _ = commands.acknowledge(
      .init(requestID: request.requestID!, target: request.target, result: .accepted))
    _ = commands.command("edit")
    field.control = .init(actions: [.editText], value: .text("external"))
    _ = commands.model.update(frame(2, [field]))
    #expect(commands.command("save").request == nil)
    #expect(commands.editor == nil)
  }

  @Test("protected input never echoes into output, history, pending updates or request metadata")
  func secureInput() throws {
    let terminal = ReaderRecordingHost()
    let surface = TerminalReaderSurface(terminal: terminal, enabled: true)
    let input = TerminalReaderInput(source: ReaderEmptyInput(), surface: surface)
    var secure = node("Password", role: .secureField)
    secure.actionTarget = "password#1"
    secure.control = .init(actions: [.setValue])
    try surface.present(frame(1, [secure]))
    func type(_ value: String) throws -> [InputEvent] {
      for char in value { _ = try input.process(.key(.character(char))) }
      return try input.process(.key(.return)).events
    }
    _ = try type("edit")
    _ = try type("replace never-print-this")
    _ = try type("read")
    let events = try type("save")
    #expect(events.count == 1)
    if case .accessibility(let request) = events.first {
      #expect(request.action == .setValue(.text("never-print-this")))
    } else {
      Issue.record("Missing secure setValue request")
    }
    #expect(!terminal.output.contains("never-print-this"))
    #expect(!surface.commands.model.history.joined().contains("never-print-this"))
    #expect(surface.commands.pendingRequest?.action == .focus)
    #expect(surface.commands.editor == nil)
  }

  @Test("reader and browser share committed actions and retain per-input acknowledgements")
  func composedRuntime() throws {
    let root = testIdentity("ReaderRuntime")
    let terminal = ReaderRecordingHost()
    let reader = TerminalReaderSurface(terminal: terminal, enabled: true)
    let surface = SharedSceneSurface(terminal: reader, terminalIsAttached: true)
    let input = TerminalReaderInput(source: ReaderEmptyInput(), surface: reader)
    var writes = 0
    let scheduler = FrameScheduler()
    let loop = RunLoop(
      rootIdentity: root, presentationSurface: surface, terminalInputReader: input,
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: FocusTracker(invalidationIdentities: [root]),
      viewBuilder: { _, _ in Button("Increase") { writes += 1 } })
    defer { loop.lifecycleCoordinator.shutdown() }
    var frames = 0
    scheduler.requestInvalidation(of: [root])
    try loop.renderPendingFrames(renderedFrames: &frames)
    _ = reader.commands.command("find Increase")
    let request = try #require(reader.commands.command("activate").request)
    _ = loop.handle(
      .scopedInput(
        .init(
          .accessibility(.init(target: request.target, action: .activate, requestID: 1)),
          origin: .browser)))
    _ = loop.handle(.scopedInput(.init(.accessibility(request), origin: .terminal)))
    try loop.renderPendingFrames(renderedFrames: &frames)
    #expect(writes == 2)
    #expect(loop.latestAccessibilityActionResponse?.requestID == 1)
    #expect(reader.commands.pendingRequest == nil)
    #expect(terminal.output.contains("Action accepted"))
    try reader.setReading(false)
    #expect(!terminal.frames.isEmpty)
    try reader.setReading(true)
    #expect(writes == 2)
    #expect(reader.commands.model.currentChunk?.node.label == "Increase")
    #expect(try input.process(.key(.character("c"), modifiers: .ctrl)).exit)
  }
}

private final class ReaderEmptyInput: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
}

private final class ReaderRecordingHost: PresentationSurface, ClipboardWritingPresentationSurface {
  let surfaceSize = CellSize(width: 40, height: 12)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  var output = ""
  var frames: [RasterSurface] = []
  var copied: String?
  @MainActor func writeClipboard(_ text: String) throws -> Bool {
    copied = text
    return true
  }
  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_ text: String) throws { output += text }
  func clearScreen() throws {}
  func moveCursor(to point: CellPoint) throws {}
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    frames.append(surface)
    return .fullRepaint(for: surface, capabilityProfile: capabilityProfile)
  }
}
