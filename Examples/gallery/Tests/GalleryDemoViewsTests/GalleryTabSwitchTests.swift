import TerminalUI
import Testing

@testable import GalleryDemoViews

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
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
      terminalInputReader: GalleryTabSwitchScriptedInput(events: events),
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
