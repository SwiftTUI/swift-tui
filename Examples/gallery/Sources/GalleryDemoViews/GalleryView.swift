import TerminalUI

/// A reference-type box for the latest non-empty palette-commands list.
///
/// Why a class instead of `@State [ActivePaletteCommand]`: @State writes
/// only take effect on the NEXT body evaluation, so updating the
/// snapshot from inside an EnvironmentReader's content closure is
/// "too late" — the sheet's `content` closure was already called
/// synchronously during the same body pass, capturing the STALE
/// snapshot. Mutating a class reference held by @State is an in-place
/// change that doesn't trigger invalidation, and any code that reads
/// the class's properties later in the same body pass sees the fresh
/// value.
@MainActor
private final class PaletteCommandHolder {
  var commands: [ActivePaletteCommand] = []
}

public struct GalleryView: View {
  public init() {}

  @State private var selection: GalleryTab = .counter
  @State private var isPaletteOpen: Bool = false
  @State private var paletteHolder = PaletteCommandHolder()

  public var body: some View {
    GalleryRuntimeBridge(
      selection: $selection,
      isPaletteOpen: $isPaletteOpen,
      paletteHolder: paletteHolder
    )
  }
}

private struct GalleryRuntimeBridge: View {
  @Binding var selection: GalleryView.GalleryTab
  @Binding var isPaletteOpen: Bool
  let paletteHolder: PaletteCommandHolder

  var body: some View {
    // `EnvironmentReader` sits on the gallery panel's resolve chain so
    // the runtime-injected `activePaletteCommands` arrives with the
    // scope-chain snapshot taken at the end of the previous frame.
    //
    // Keep the Gallery's stateful surface outside this bridge so
    // environment-driven re-resolves do not recreate the tab-selection
    // owner.
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

      Tab("Physics", value: GalleryView.GalleryTab.physics) {
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
      name: "Switch to File Drop",
      action: { selection = .fileDrop }
    )
    .paletteCommand(
      name: "Switch to Physics",
      action: { selection = .physics }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) {
      // Read from the class holder at sheet-content construction
      // time. Because we mutated holder.commands earlier in this
      // same body pass (inside the EnvironmentReader closure), the
      // read here sees the freshest value — not whatever was there
      // before.
      CommandPaletteList(
        commands: paletteHolder.commands,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
    // Nothing to snapshot at this point — the class-backed
    // `paletteHolder.commands` is kept up-to-date continuously by
    // the EnvironmentReader above. Opening the sheet is enough;
    // the palette owns its own query/focus state now.
    isPaletteOpen = true
  }
}

extension GalleryView {
  enum GalleryTab: Hashable {
    case counter
    case todo
    case calculator
    case bordersAndShapes
    case images
    case animations
    case fileDrop
    case physics
  }
}
