import Dispatch
@_spi(Runners) @_spi(Testing) import SwiftTUI
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
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTabSwitchClickTest")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GalleryView(),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTabSwitchClickTest.BoundsProbe")
      ])
    )

    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      terminalSize: terminalSize,
      events: [
        .mouse(.init(kind: .down(.primary), location: todoClickCenter)),
        .mouse(.init(kind: .up(.primary), location: todoClickCenter)),
      ],
      rootIdentity: rootIdentity,
      viewBuilder: { GalleryView() }
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
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteSelectionRegression")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GallerySelectionSeedHarness(initialSelection: .counter),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteSelectionRegression.TodoBoundsProbe")]
      )
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteSelectionRegression.DeleteBoundsProbe")]
      ),
      chooseTopMost: true
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
      viewBuilder: { GallerySelectionSeedHarness(initialSelection: .counter) }
    )

    let surface = try #require(host.lastPresentedSurface).lines.joined(separator: "\n")
    #expect(
      surface.contains("remaining"),
      "expected the Todo tab to stay selected after deleting the top row; surface was:\n\(surface)"
    )
  }

  @Test("real terminal host stays on Todo after deleting the top todo row")
  func realTerminalHostDeletingTopTodoRowKeepsTodoVisible() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryTodoDeleteRealTerminalHost")])
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GallerySelectionSeedHarness(initialSelection: .counter),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteRealTerminalHost.TodoBoundsProbe")
      ])
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(
        components: [.named("GalleryTodoDeleteRealTerminalHost.DeleteBoundsProbe")]
      ),
      chooseTopMost: true
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
        presentationSurface: host,
        terminalInputReader: inputReader,
        terminalSize: terminalSize,
        rootIdentity: rootIdentity,
        viewBuilder: { GallerySelectionSeedHarness(initialSelection: .counter) }
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

    let stableAfterDeleteScreen = try await Self.observeScreenWhileAbsent(
      on: pty.master,
      screen: &screen,
      timeoutNanoseconds: 400_000_000
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
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
    #expect(
      !stableAfterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected follow-up frames to stay on Todo after deleting the top row; screen was:\n\(stableAfterDeleteScreen)"
    )
    #expect(
      stableAfterDeleteScreen.contains("2 remaining"),
      "expected the deletion to persist across follow-up frames; screen was:\n\(stableAfterDeleteScreen)"
    )
  }

  @Test(
    "opening and dismissing the palette keeps Physics progress while Physics stays selected")
  func paletteOpenAndDismissKeepsPhysicsProgress() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let rootIdentity = Identity(components: [.named("GalleryPhysicsPaletteContinuity")])
    let view = GallerySelectionSeedHarness(initialSelection: .physics)
    let host = GalleryTabSwitchRecordingHost(size: terminalSize)
    let capture = GallerySurfaceCapture()

    let result = try await Self.runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchAwaitedInputReader(steps: [
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
          let surfaces = deduplicated(host.surfaces)
          guard surfaces.count >= 2 else {
            return false
          }
          capture.initialPhysicsSurface = capture.initialPhysicsSurface ?? surfaces.first
          capture.prePaletteSurface = surfaces.last
          return capture.prePaletteSurface != capture.initialPhysicsSurface
        },
        .event(.key(KeyPress(.character("k"), modifiers: .ctrl))),
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
          let text = host.lastPresentedSurface?.lines.joined(separator: "\n") ?? ""
          return text.contains("Command palette")
        },
        .event(.key(KeyPress(.escape, modifiers: []))),
        .waitUntil(timeoutNanoseconds: 2_000_000_000) {
          guard let surface = host.lastPresentedSurface else {
            return false
          }
          let text = surface.lines.joined(separator: "\n")
          guard !text.contains("Command palette"), !text.contains("palette sheet") else {
            return false
          }
          capture.postDismissSurface = surface
          return true
        },
        .event(.key(KeyPress(.character("d"), modifiers: .ctrl))),
      ]),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: { view }
    )

    let initialPhysicsSurface = try #require(capture.initialPhysicsSurface)
    let prePaletteSurface = try #require(capture.prePaletteSurface)
    let postDismissSurface = try #require(capture.postDismissSurface)
    let postDismissText = postDismissSurface.lines.joined(separator: "\n")

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(
      prePaletteSurface != initialPhysicsSurface,
      "expected fullscreen animation to advance before opening the palette"
    )
    #expect(
      postDismissSurface != initialPhysicsSurface,
      "dismissing the palette should not recreate the physics tab at its initial spawn frame"
    )
    #expect(
      !postDismissText.contains("A SwiftUI-shaped terminal UI"),
      "dismissing the palette should keep the Full Screen tab selected; surface was:\n\(postDismissText)"
    )
  }

  @Test("scene-hosted gallery stays on Todo after deleting the top todo row")
  func sceneHostedGalleryDeletingTopTodoRowKeepsTodoVisible() async throws {
    let terminalSize = CellSize(width: 80, height: 24)
    let todoClickCenter = try Self.centerOfText(
      "Todo",
      in: GalleryView(),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteSceneHostedBounds.TodoProbe")
      ])
    )
    let deleteClickCenter = try Self.centerOfText(
      "×",
      in: GallerySelectionSeedHarness(initialSelection: .todo),
      terminalSize: terminalSize,
      rootIdentity: Identity(components: [
        .named("GalleryTodoDeleteSceneHostedBounds.DeleteProbe")
      ]),
      chooseTopMost: true
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
      try await Self.runSceneHarness(
        scene: WindowGroup("Gallery Window") {
          GalleryView()
        },
        presentationSurface: host,
        terminalInputReader: inputReader,
        sessionName: "GalleryTabSwitchTests.SceneHostedGalleryDelete"
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

    let stableAfterDeleteScreen = try await Self.observeScreenWhileAbsent(
      on: pty.master,
      screen: &screen,
      timeoutNanoseconds: 400_000_000
    ) { rendered in
      rendered.contains("A SwiftUI-shaped terminal UI")
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
    #expect(
      !stableAfterDeleteScreen.contains("A SwiftUI-shaped terminal UI"),
      "expected follow-up frames to stay on Todo after deleting the top row; screen was:\n\(stableAfterDeleteScreen)"
    )
    #expect(
      stableAfterDeleteScreen.contains("2 remaining"),
      "expected the deletion to persist across follow-up frames; screen was:\n\(stableAfterDeleteScreen)"
    )
  }

  private static func boundsOfText(
    _ target: String,
    in node: PlacedNode,
    chooseTopMost: Bool = false
  ) -> CellRect? {
    var matches: [CellRect] = []
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

  private static func centerOfText(
    _ target: String,
    in view: some View,
    terminalSize: CellSize,
    rootIdentity: Identity,
    chooseTopMost: Bool = false
  ) throws -> Point {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      AnyView(view),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let bounds = try #require(
      Self.boundsOfText(target, in: artifacts.placedTree, chooseTopMost: chooseTopMost)
    )
    return Self.centerPoint(of: bounds)
  }

  private static func collectBoundsOfText(
    _ target: String,
    in node: PlacedNode,
    into matches: inout [CellRect]
  ) {
    if case .text(let content) = node.drawPayload, content == target {
      matches.append(node.bounds)
    }
    for child in node.children {
      collectBoundsOfText(target, in: child, into: &matches)
    }
  }

  private static func centerPoint(of rect: CellRect) -> Point {
    Point(
      CellPoint(
        x: rect.origin.x + rect.size.width / 2,
        y: rect.origin.y + rect.size.height / 2
      )
    )
  }

  @MainActor
  private static func runHarness<V: View>(
    host: GalleryTabSwitchRecordingHost,
    terminalSize: CellSize,
    events: [InputEvent],
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    try await runHarness(
      presentationSurface: host,
      terminalInputReader: GalleryTabSwitchScriptedInput(events: events),
      terminalSize: terminalSize,
      rootIdentity: rootIdentity,
      viewBuilder: viewBuilder
    )
  }

  @MainActor
  private static func runHarness<V: View>(
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    terminalSize: CellSize,
    rootIdentity: Identity,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: presentationSurface,
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

  @MainActor
  private static func runSceneHarness<S: Scene>(
    scene: S,
    presentationSurface: any PresentationSurface,
    terminalInputReader: any TerminalInputReading,
    sessionName: String
  ) async throws -> RunLoopResult<SceneSessionState> {
    let selections = collectWindowSceneSelections(from: scene)
    guard let selection = selections.first else {
      throw AppLaunchError.noScenes
    }
    guard selections.count == 1 else {
      fatalError("expected a single scene for the gallery test harness")
    }

    return try await selection.run(
      sessionName: sessionName,
      resources: .init(
        presentationSurface: presentationSurface,
        terminalInputReader: terminalInputReader,
        signalReader: GalleryTabSwitchEmptySignals(),
        scheduler: FrameScheduler()
      ),
      stateContainer: StateContainer(
        initialState: SceneSessionState(),
        invalidationIdentities: [selection.rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [selection.rootIdentity]
      )
    )
  }

  private static func makePseudoTerminal(
    size: CellSize
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
    let cell = point.containingCell
    return Array(
      "\u{001B}[<0;\(cell.x + 1);\(cell.y + 1)M\u{001B}[<0;\(cell.x + 1);\(cell.y + 1)m"
        .utf8
    )
  }

  private enum ScreenWaitError: Error, CustomStringConvertible {
    case timedOut(rendered: String)
    case forbiddenStateObserved(rendered: String)

    var description: String {
      switch self {
      case .timedOut(let rendered):
        "Timed out waiting for screen condition; last screen was:\n\(rendered)"
      case .forbiddenStateObserved(let rendered):
        "Observed forbidden screen state:\n\(rendered)"
      }
    }
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
    rendered = screen.renderedText
    if condition(rendered) {
      return rendered
    }
    throw ScreenWaitError.timedOut(rendered: rendered)
  }

  private static func observeScreenWhileAbsent(
    on fileDescriptor: Int32,
    screen: inout PTYVisibleScreen,
    timeoutNanoseconds: UInt64,
    pollNanoseconds: UInt64 = 5_000_000,
    forbidden: (String) -> Bool
  ) async throws -> String {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    var rendered = screen.renderedText
    if forbidden(rendered) {
      throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
    }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let bytes = try readAvailableBytes(from: fileDescriptor)
      if !bytes.isEmpty {
        screen.feed(bytes)
        rendered = screen.renderedText
      }
      if forbidden(rendered) {
        throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
      }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }

    let finalBytes = try readAvailableBytes(from: fileDescriptor)
    if !finalBytes.isEmpty {
      screen.feed(finalBytes)
    }
    rendered = screen.renderedText
    if forbidden(rendered) {
      throw ScreenWaitError.forbiddenStateObserved(rendered: rendered)
    }
    return rendered
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

private struct GallerySelectionSeedHarness: View {
  @State private var selection: GalleryView.GalleryTab
  @State private var isPaletteOpen = false

  init(initialSelection: GalleryView.GalleryTab) {
    _selection = State(initialValue: initialSelection)
  }

  var body: some View {
    GallerySelectionRuntimeBridge(
      selection: $selection,
      isPaletteOpen: $isPaletteOpen
    )
  }
}

private struct GallerySelectionRuntimeBridge: View {
  @Binding var selection: GalleryView.GalleryTab
  @Binding var isPaletteOpen: Bool

  var body: some View {
    galleryBody()
  }

  private func galleryBody() -> some View {
    TabView(selection: $selection) {
      Tab("Counter", value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }

      Tab("Todo", value: GalleryView.GalleryTab.todo) {
        TodoTab()
      }

      Tab("Text Input", value: GalleryView.GalleryTab.textInput) {
        TextInputTab()
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

      Tab("Full Screen", value: GalleryView.GalleryTab.physics) {
        PhysicsTab()
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
      name: "Switch to Text Input",
      action: { selection = .textInput }
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
      action: { selection = .physics }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
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

private enum GalleryTabSwitchAwaitedInputStep {
  case event(InputEvent, delayNanoseconds: UInt64 = 0)
  case waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor () -> Bool
  )
}

private final class GalleryTabSwitchAwaitedInputReader: TerminalInputReading {
  private let steps: [GalleryTabSwitchAwaitedInputStep]
  private let pollNanoseconds: UInt64

  init(
    steps: [GalleryTabSwitchAwaitedInputStep],
    pollNanoseconds: UInt64 = 10_000_000
  ) {
    self.steps = steps
    self.pollNanoseconds = pollNanoseconds
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let steps = self.steps
      let pollNanoseconds = self.pollNanoseconds
      let task = Task { @MainActor in
        for step in steps {
          switch step {
          case .event(let event, let delayNanoseconds):
            if delayNanoseconds > 0 {
              try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            continuation.yield(event)
          case .waitUntil(let timeoutNanoseconds, let predicate):
            var elapsedNanoseconds: UInt64 = 0
            while !predicate() && elapsedNanoseconds < timeoutNanoseconds {
              try? await Task.sleep(nanoseconds: pollNanoseconds)
              elapsedNanoseconds += pollNanoseconds
            }
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
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

private final class GalleryTabSwitchRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var surfaces: [RasterSurface] = []
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    surfaces.append(surface)
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

@MainActor
private final class GallerySurfaceCapture {
  var initialPhysicsSurface: RasterSurface?
  var prePaletteSurface: RasterSurface?
  var postDismissSurface: RasterSurface?
}

private func deduplicated(
  _ surfaces: [RasterSurface]
) -> [RasterSurface] {
  var result: [RasterSurface] = []
  result.reserveCapacity(surfaces.count)
  for surface in surfaces where result.last != surface {
    result.append(surface)
  }
  return result
}

private struct PTYVisibleScreen {
  private var size: CellSize
  private var cells: [[Character]]
  private var cursor = CellPoint.zero
  private var pendingBytes: [UInt8] = []

  init(size: CellSize) {
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
      cursor = CellPoint(
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
