import TerminalUI

public struct GalleryView: View {
  public init() {}

  @State private var selection: Tab = .counter
  @State private var isPaletteOpen: Bool = false
  @State private var paletteSnapshot: [ActivePaletteCommand] = []

  public var body: some View {
    // `EnvironmentReader` sits on the gallery panel's resolve chain so
    // the runtime-injected `activePaletteCommands` arrives with the
    // scope-chain snapshot taken at the end of the previous frame.
    // The key-command and toolbar-item actions close over that value
    // and snapshot it into `paletteSnapshot` when the palette opens.
    EnvironmentReader(\.activePaletteCommands) { commands in
      galleryBody(commands: commands)
    }
  }

  private func galleryBody(
    commands: [ActivePaletteCommand]
  ) -> some View {
    TabView(selection: $selection) {
      CounterTab()
        .tabItem("Counter")
        .tag(Tab.counter)

      TodoTab()
        .tabItem("Todo")
        .tag(Tab.todo)

      CalculatorTab()
        .tabItem("Calculator")
        .tag(Tab.calculator)

      BordersAndShapesTab()
        .tabItem("Borders & Shapes")
        .tag(Tab.bordersAndShapes)

      ImagesTab()
        .tabItem("Images")
        .tag(Tab.images)

      AnimationsTab()
        .tabItem("Animations")
        .tag(Tab.animations)

      FullScreenTab()
        .tabItem("Full Screen")
        .tag(Tab.fullScreen)
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(
      .init(
        title: "⌃K Palette",
        action: { openPalette(using: commands) }
      )
    )
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { openPalette(using: commands) }
    )
    // Terminal input: Ctrl+digit has no distinct control-code mapping,
    // so terminals drop the modifier. Use Alt+digit (ESC+digit escape
    // sequence) — the same convention tmux/screen use for pane
    // switching.
    .keyCommand(
      "Switch to Counter",
      key: .character("1"),
      modifiers: .alt,
      action: { selection = .counter }
    )
    .keyCommand(
      "Switch to Todo",
      key: .character("2"),
      modifiers: .alt,
      action: { selection = .todo }
    )
    .keyCommand(
      "Switch to Calculator",
      key: .character("3"),
      modifiers: .alt,
      action: { selection = .calculator }
    )
    .keyCommand(
      "Switch to Borders & Shapes",
      key: .character("4"),
      modifiers: .alt,
      action: { selection = .bordersAndShapes }
    )
    .keyCommand(
      "Switch to Images",
      key: .character("5"),
      modifiers: .alt,
      action: { selection = .images }
    )
    .keyCommand(
      "Switch to Animations",
      key: .character("6"),
      modifiers: .alt,
      action: { selection = .animations }
    )
    .keyCommand(
      "Switch to Full Screen",
      key: .character("7"),
      modifiers: .alt,
      action: { selection = .fullScreen }
    )
    .paletteCommand(
      name: "Switch to Counter",
      description: "⌥1",
      action: { selection = .counter }
    )
    .paletteCommand(
      name: "Switch to Todo",
      description: "⌥2",
      action: { selection = .todo }
    )
    .paletteCommand(
      name: "Switch to Calculator",
      description: "⌥3",
      action: { selection = .calculator }
    )
    .paletteCommand(
      name: "Switch to Borders & Shapes",
      description: "⌥4",
      action: { selection = .bordersAndShapes }
    )
    .paletteCommand(
      name: "Switch to Images",
      description: "⌥5",
      action: { selection = .images }
    )
    .paletteCommand(
      name: "Switch to Animations",
      description: "⌥6",
      action: { selection = .animations }
    )
    .paletteCommand(
      name: "Switch to Full Screen",
      description: "⌥7",
      action: { selection = .fullScreen }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .sheet("Command palette", isPresented: $isPaletteOpen) {
      CommandPaletteList(
        commands: paletteSnapshot,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette(using commands: [ActivePaletteCommand]) {
    paletteSnapshot = commands
    isPaletteOpen = true
  }
}

extension GalleryView {
  enum Tab: Hashable {
    case counter
    case todo
    case calculator
    case bordersAndShapes
    case images
    case animations
    case fullScreen
  }
}
