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
    // Tab switching is palette-driven: open with ⌃K, fuzzy-filter the
    // list. No per-tab keybindings — the palette is the discovery
    // surface.
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
      name: "Switch to Full Screen",
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
