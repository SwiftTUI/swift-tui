import Dispatch
import TerminalUI
import Testing

@testable import GalleryDemoViews

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@MainActor
@Suite
struct GalleryTabSwitchTests {
  @Test("gallery tabs collapse into the overflow trigger instead of ellipsizing")
  func galleryTabsCollapseIntoOverflowTrigger() {
    var env = EnvironmentValues()
    env.terminalSize = .init(width: 80, height: 24)

    let artifacts = DefaultRenderer().render(
      GalleryView(),
      context: .init(
        identity: Identity(components: [.named("GalleryTabOverflowSurfaceTest")]),
        environmentValues: env
      ),
      proposal: .init(width: 40, height: 24)
    )

    let surface = artifacts.rasterSurface.lines.prefix(3).joined(separator: "\n")
    #expect(surface.contains("▾"))
    #expect(surface.contains("…") == false)
  }

  @Test("clicking a gallery tab switches tabs without crashing")
  func clickingGalleryTabSwitchesSelection() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTabSwitchClickTest")])
    let view = GalleryView()

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let todoBounds = try #require(Self.boundsOfText("Todo", in: initial.placedTree))
    let clickCenter = Point(
      x: todoBounds.origin.x + todoBounds.size.width / 2,
      y: todoBounds.origin.y + todoBounds.size.height / 2
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: clickCenter)),
        .mouse(.init(kind: .up(.primary), location: clickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let lastPresented = try #require(host.lastPresentedSurface)
    let surface = lastPresented.lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected Todo tab content after clicking the Todo tab; surface was:\n\(surface)"
    )
  }

  @Test("deleting the top todo row does not switch the gallery back to Counter")
  func deletingTopTodoRowKeepsTodoSelected() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteSelectionRegression")])
    let view = GallerySelectionSeedHarness(initialSelection: .counter)

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let todoBounds = try #require(Self.boundsOfText("Todo", in: initial.placedTree))
    let todoClickCenter = Point(
      x: todoBounds.origin.x + todoBounds.size.width / 2,
      y: todoBounds.origin.y + todoBounds.size.height / 2
    )

    let todoSelected = DefaultRenderer().render(
      GallerySelectionSeedHarness(initialSelection: .todo),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let deleteBounds = try #require(
      Self.boundsOfText("×", in: todoSelected.placedTree, chooseTopMost: true)
    )
    let deleteClickCenter = Point(
      x: deleteBounds.origin.x + deleteBounds.size.width / 2,
      y: deleteBounds.origin.y + deleteBounds.size.height / 2
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .up(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .down(.primary), location: deleteClickCenter)),
        .mouse(.init(kind: .up(.primary), location: deleteClickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let surface = try #require(host.lastPresentedSurface).lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected the Todo tab to stay selected after deleting the top row; surface was:\n\(surface)"
    )
  }

  @Test("real terminal host stays on Todo after deleting the top todo row")
  func realTerminalHostDeletingTopTodoRowKeepsTodoVisible() async throws {
    let terminalSize = Size(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteRealTerminalHost")])
    let view = GallerySelectionSeedHarness(initialSelection: .counter)

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let todoBounds = try #require(Self.boundsOfText("Todo", in: initial.placedTree))
    let todoClickCenter = Point(
      x: todoBounds.origin.x + todoBounds.size.width / 2,
      y: todoBounds.origin.y + todoBounds.size.height / 2
    )

    let todoSelected = DefaultRenderer().render(
      GallerySelectionSeedHarness(initialSelection: .todo),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let deleteBounds = try #require(
      Self.boundsOfText("×", in: todoSelected.placedTree, chooseTopMost: true)
    )
    let deleteClickCenter = Point(
      x: deleteBounds.origin.x + deleteBounds.size.width / 2,
      y: deleteBounds.origin.y + deleteBounds.size.height / 2
    )

    let pty = try #require(Self.makePseudoTerminal(size: terminalSize))
    defer {
      _ = close(pty.master)
      _ = close(pty.slave)
    }

    let host = TerminalHost(
      inputFileDescriptor: pty.slave,
      outputFileDescriptor: pty.slave,
      fallbackSize: terminalSize,
      capabilityProfile: .previewUnicode
    )
    let inputReader = InputReader(fileDescriptor: pty.slave)

    let runTask = Task {
      try await Self.runHarness(
        terminalHost: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { view }
      )
    }

    var screen = PTYVisibleScreen(size: terminalSize)

    let initialScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("Counter") && rendered.contains("Todo")
    }
    #expect(
      initialScreen.contains("Counter"),
      "expected the initial gallery frame to render; screen was:\n\(initialScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: todoClickCenter),
      to: pty.master
    )

    let todoScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && rendered.contains("Write docs")
    }
    #expect(
      todoScreen.contains("remaining"),
      "expected the Todo tab after clicking Todo; screen was:\n\(todoScreen)"
    )

    try Self.writeAllBytes(
      Self.sgrPrimaryClick(at: deleteClickCenter),
      to: pty.master
    )

    let afterDeleteScreen = try await Self.waitForScreen(
      on: pty.master,
      screen: &screen
    ) { rendered in
      rendered.contains("remaining") && !rendered.contains("Write docs")
    }

    _ = close(pty.master)

    _ = try await runTask.value

    #expect(
      afterDeleteScreen.contains("remaining"),
      "expected the Todo tab to remain visible after deleting the top row; screen was:\n\(afterDeleteScreen)"
    )
    #expect(
      !afterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected not to snap back to the Counter tab; screen was:\n\(afterDeleteScreen)"
    )
  }

  private static func boundsOfText(
    _ target: String,
    in node: PlacedNode,
    chooseTopMost: Bool = false
  ) -> Rect? {
    var matches: [Rect] = []
    collectBoundsOfText(target, in: node, into: &matches)
    guard !matches.isEmpty else {
      return nil
    }
    if chooseTopMost {
      return matches.min(by: {
        if $0.origin.y == $1.origin.y {
          return $0.origin.x < $1.origin.x
        }
        return $0.origin.y < $1.origin.y
      })
    }
    return matches.first
  }

  private static func collectBoundsOfText(
    _ target: String,
    in node: PlacedNode,
    into matches: inout [Rect]
  ) {
    if case .text(let content) = node.drawPayload, content == target {
      matches.append(node.bounds)
    }
    for child in node.children {
      collectBoundsOfText(target, in: child, into: &matches)
    }
  }

  @MainActor
  private static func runHarness<V: View>(
    host: GalleryTabSwitchRecordingHost,
    terminalSize: Size,
    events: [InputEvent],
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    try await runHarness(
      terminalHost: host,
      terminalInputReader: GalleryTabSwitchScriptedInput(events: events),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: viewBuilder
    )
  }

  @MainActor
  private static func runHarness<V: View>(
    terminalHost: any TerminalHosting,
    terminalInputReader: any TerminalInputReading,
    terminalSize: Size,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: terminalHost,
      terminalInputReader: terminalInputReader,
      signalReader: GalleryTabSwitchEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    return try await runLoop.run()
  }

  private static func makePseudoTerminal(
    size: Size
  ) -> (master: Int32, slave: Int32)? {
    var master: Int32 = -1
    var slave: Int32 = -1
    var windowSize = winsize(
      ws_row: UInt16(max(1, size.height)),
      ws_col: UInt16(max(1, size.width)),
      ws_xpixel: 0,
      ws_ypixel: 0
    )

    guard
      openpty(
        &master,
        &slave,
        nil,
        nil,
        &windowSize
      ) == 0
    else {
      return nil
    }

    let currentFlags = fcntl(master, F_GETFL)
    guard currentFlags >= 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }
    guard fcntl(master, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
      _ = close(master)
      _ = close(slave)
      return nil
    }

    return (master, slave)
  }

  private static func writeAllBytes(
    _ bytes: [UInt8],
    to fileDescriptor: Int32
  ) throws {
    var totalBytesWritten = 0

    try unsafe bytes.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        return
      }

      while totalBytesWritten < bytes.count {
        let nextAddress = unsafe baseAddress.advanced(by: totalBytesWritten)
        let bytesRemaining = bytes.count - totalBytesWritten
        let bytesWritten = unsafe write(fileDescriptor, nextAddress, bytesRemaining)
        guard bytesWritten >= 0 else {
          throw TerminalHostError.failedToWrite(errno: errno)
        }
        totalBytesWritten += bytesWritten
      }
    }
  }

  private static func sgrPrimaryClick(
    at point: Point
  ) -> [UInt8] {
    Array(
      "\u{001B}[<0;\(point.x + 1);\(point.y + 1)M\u{001B}[<0;\(point.x + 1);\(point.y + 1)m"
        .utf8
    )
  }

  private static func waitForScreen(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 5_000_000,
    condition: (String) -> Bool
  ) async throws -> String {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    var rendered = screen.renderedText

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let bytes = try readAvailableBytes(from: fileDescriptor)
      if !bytes.isEmpty {
        screen.feed(bytes)
        rendered = screen.renderedText
      }
      if condition(rendered) {
        return rendered
      }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }

    let finalBytes = try readAvailableBytes(from: fileDescriptor)
    if !finalBytes.isEmpty {
      screen.feed(finalBytes)
    }
    return screen.renderedText
  }

  private static func readAvailableBytes(
    from fileDescriptor: Int32
  ) throws -> [UInt8] {
    var collected: [UInt8] = []

    while true {
      var buffer = Array(repeating: UInt8(0), count: 4096)
      let bytesRead = unsafe read(fileDescriptor, &buffer, buffer.count)

      if bytesRead > 0 {
        collected.append(contentsOf: buffer.prefix(Int(bytesRead)))
        continue
      }

      if bytesRead == 0 {
        break
      }

      if errno == EAGAIN || errno == EWOULDBLOCK {
        break
      }

      throw TerminalHostError.failedToReadWindowSize(errno: errno)
    }

    return collected
  }
}

@MainActor
private final class TestPaletteCommandHolder {
  var commands: [ActivePaletteCommand] = []
}

private struct GallerySelectionSeedHarness: View {
  @State private var selection: GalleryView.GalleryTab
  @State private var isPaletteOpen = false
  @State private var paletteHolder = TestPaletteCommandHolder()
  @State private var paletteQuery = ""
  @FocusState private var isPaletteQueryFocused: Bool

  init(initialSelection: GalleryView.GalleryTab) {
    _selection = State(initialValue: initialSelection)
  }

  var body: some View {
    GallerySelectionRuntimeBridge(
      selection: $selection,
      isPaletteOpen: $isPaletteOpen,
      paletteHolder: paletteHolder,
      paletteQuery: $paletteQuery,
      isPaletteQueryFocused: $isPaletteQueryFocused
    )
  }
}

private struct GallerySelectionRuntimeBridge: View {
  @Binding var selection: GalleryView.GalleryTab
  @Binding var isPaletteOpen: Bool
  let paletteHolder: TestPaletteCommandHolder
  @Binding var paletteQuery: String
  let isPaletteQueryFocused: FocusState<Bool>.Binding

  var body: some View {
    EnvironmentReader(\.activePaletteCommands) { commands in
      if !commands.isEmpty {
        paletteHolder.commands = commands
      }
      return galleryBody()
    }
  }

  private func galleryBody() -> some View {
    TabView(selection: $selection) {
      Tab("Counter", value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }

      Tab("Todo", value: GalleryView.GalleryTab.todo) {
        TodoTab()
      }

      Tab("Calculator", value: GalleryView.GalleryTab.calculator) {
        CalculatorTab()
      }

      Tab("Borders & Shapes", value: GalleryView.GalleryTab.bordersAndShapes) {
        BordersAndShapesTab()
      }

      Tab("Images", value: GalleryView.GalleryTab.images) {
        ImagesTab()
      }

      Tab("Animations", value: GalleryView.GalleryTab.animations) {
        AnimationsTab()
      }

      Tab("File Drop", value: GalleryView.GalleryTab.fileDrop) {
        FileDropTab()
      }

      Tab("Full Screen", value: GalleryView.GalleryTab.fullScreen) {
        FullScreenTab()
      }
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(
      .init(
        title: "⌃K Palette",
        action: { openPalette() }
      )
    )
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { openPalette() }
    )
    .paletteCommand(
      name: "Switch to Counter",
      action: { selection = .counter }
    )
    .paletteCommand(
      name: "Switch to Todo",
      action: { selection = .todo }
    )
    .paletteCommand(
      name: "Switch to Calculator",
      action: { selection = .calculator }
    )
    .paletteCommand(
      name: "Switch to Borders & Shapes",
      action: { selection = .bordersAndShapes }
    )
    .paletteCommand(
      name: "Switch to Images",
      action: { selection = .images }
    )
    .paletteCommand(
      name: "Switch to Animations",
      action: { selection = .animations }
    )
    .paletteCommand(
      name: "Switch to File Drop",
      action: { selection = .fileDrop }
    )
    .paletteCommand(
      name: "Switch to Full Screen",
      action: { selection = .fullScreen }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) {
      CommandPaletteList(
        commands: paletteHolder.commands,
        query: $paletteQuery,
        isQueryFocused: isPaletteQueryFocused,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
    paletteQuery = ""
    isPaletteQueryFocused.wrappedValue = true
    isPaletteOpen = true
  }
}

private final class GalleryTabSwitchScriptedInput: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class GalleryTabSwitchEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class GalleryTabSwitchRecordingHost: TerminalHosting {
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: Size) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

private struct PTYVisibleScreen {
  private var size: Size
  private var cells: [[Character]]
  private var cursor = Point.zero
  private var pendingBytes: [UInt8] = []

  init(size: Size) {
    self.size = size
    cells = Array(
      repeating: Array(repeating: " ", count: max(1, size.width)),
      count: max(1, size.height)
    )
  }

  var renderedText: String {
    cells
      .map { row in
        var endIndex = row.endIndex
        while endIndex > row.startIndex, row[row.index(before: endIndex)] == " " {
          endIndex = row.index(before: endIndex)
        }
        return String(row[..<endIndex])
      }
      .joined(separator: "\n")
  }

  mutating func feed(
    _ bytes: [UInt8]
  ) {
    pendingBytes.append(contentsOf: bytes)

    var index = 0
    while index < pendingBytes.count {
      let byte = pendingBytes[index]

      if byte == 0x1B {
        guard index + 1 < pendingBytes.count else {
          break
        }

        let next = pendingBytes[index + 1]
        if next == 0x5B {
          guard let consumed = consumeCSI(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        if next == 0x5D || next == 0x5F {
          guard let consumed = consumeStringEscape(startingAt: index) else {
            break
          }
          index = consumed
          continue
        }

        index += 2
        continue
      }

      if byte == 0x0D {
        cursor.x = 0
        index += 1
        continue
      }

      if byte == 0x0A {
        cursor.x = 0
        cursor.y = min(max(0, size.height - 1), cursor.y + 1)
        index += 1
        continue
      }

      if byte < 0x20 {
        index += 1
        continue
      }

      if byte < 0x80 {
        write(Character(UnicodeScalar(Int(byte))!))
        index += 1
        continue
      }

      let sequenceLength = utf8SequenceLength(for: byte)
      guard index + sequenceLength <= pendingBytes.count else {
        break
      }
      write("•")
      index += sequenceLength
    }

    if index > 0 {
      pendingBytes.removeFirst(index)
    }
  }

  private mutating func consumeCSI(
    startingAt startIndex: Int
  ) -> Int? {
    var index = startIndex + 2
    while index < pendingBytes.count {
      let byte = pendingBytes[index]
      if (0x40...0x7E).contains(byte) {
        let parameters = Array(pendingBytes[(startIndex + 2)..<index])
        applyCSI(parameters: parameters, command: byte)
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func consumeStringEscape(
    startingAt startIndex: Int
  ) -> Int? {
    var index = startIndex + 2
    while index + 1 < pendingBytes.count {
      if pendingBytes[index] == 0x1B, pendingBytes[index + 1] == 0x5C {
        return index + 2
      }
      if pendingBytes[index] == 0x07 {
        return index + 1
      }
      index += 1
    }
    return nil
  }

  private mutating func applyCSI(
    parameters: [UInt8],
    command: UInt8
  ) {
    let parameterString = String(decoding: parameters, as: UTF8.self)
    let privateMode = parameterString.hasPrefix("?")
    let cleanedParameters =
      privateMode
      ? String(parameterString.dropFirst())
      : parameterString
    let values = cleanedParameters.split(separator: ";").compactMap { Int($0) }

    switch command {
    case 0x48, 0x66:  // H, f
      let row = max(1, values.first ?? 1) - 1
      let column = max(1, values.dropFirst().first ?? 1) - 1
      cursor = Point(
        x: min(max(0, size.width - 1), column),
        y: min(max(0, size.height - 1), row)
      )
    case 0x4A:  // J
      if values.first == 2 || values.isEmpty {
        clearAll()
      }
    case 0x4B:  // K
      eraseToEndOfLine()
    case 0x43:  // C
      cursor.x = min(max(0, size.width - 1), cursor.x + max(1, values.first ?? 1))
    case 0x44:  // D
      cursor.x = max(0, cursor.x - max(1, values.first ?? 1))
    case 0x41:  // A
      cursor.y = max(0, cursor.y - max(1, values.first ?? 1))
    case 0x42:  // B
      cursor.y = min(max(0, size.height - 1), cursor.y + max(1, values.first ?? 1))
    case 0x47:  // G
      cursor.x = min(max(0, size.width - 1), max(1, values.first ?? 1) - 1)
    case 0x6D, 0x68, 0x6C:  // m, h, l
      return
    default:
      return
    }
  }

  private mutating func clearAll() {
    for row in cells.indices {
      for column in cells[row].indices {
        cells[row][column] = " "
      }
    }
    cursor = .zero
  }

  private mutating func eraseToEndOfLine() {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    let row = cursor.y
    guard cursor.x >= 0, cursor.x < cells[row].count else {
      return
    }
    for column in cursor.x..<cells[row].count {
      cells[row][column] = " "
    }
  }

  private mutating func write(
    _ character: Character
  ) {
    guard cursor.y >= 0, cursor.y < cells.count else {
      return
    }
    guard cursor.x >= 0, cursor.x < cells[cursor.y].count else {
      return
    }
    cells[cursor.y][cursor.x] = character
    cursor.x += 1
  }

  private func utf8SequenceLength(
    for byte: UInt8
  ) -> Int {
    switch byte {
    case 0xC0...0xDF:
      2
    case 0xE0...0xEF:
      3
    case 0xF0...0xF7:
      4
    default:
      1
    }
  }
}
