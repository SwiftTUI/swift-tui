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

  @State private var selection: Tab = .counter
  @State private var isPaletteOpen: Bool = false
  @State private var paletteHolder = PaletteCommandHolder()
  // The palette's TextField state and focus binding live HERE, not
  // inside `CommandPaletteList`, because sheet-content views inherit
  // their parent's authoring context (see `View.resolveBody` in
  // `State.swift:383` — it reuses the current authoring context when
  // one is set, and `ScopedBuilder` captures this view's context at
  // sheet-construction time). Declaring `@State` / `@FocusState`
  // inside the sheet's content view would route those property
  // wrappers' state slots through THIS view's viewNode, where they
  // can collide with this view's own `@State` slots by source-line
  // ordinal — the exact crash pattern observed before this refactor
  // (`ViewNode.stateSlot` type-mismatch on a slot previously
  // initialized by `@State selection: Tab`).
  @State private var paletteQuery: String = ""
  @FocusState private var isPaletteQueryFocused: Bool

  public var body: some View {
    // `EnvironmentReader` sits on the gallery panel's resolve chain so
    // the runtime-injected `activePaletteCommands` arrives with the
    // scope-chain snapshot taken at the end of the previous frame.
    //
    // We update `paletteHolder.commands` INSIDE the reader's content
    // closure so the sheet's content (built further down in the same
    // synchronous body pass) reads the freshest value. Using a class
    // holder lets us side-effect without triggering @State
    // invalidation loops.
    EnvironmentReader(\.activePaletteCommands) { commands in
      if !commands.isEmpty {
        paletteHolder.commands = commands
      }
      return galleryBody()
    }
  }

  private func galleryBody() -> some View {
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

      FileDropTab()
        .tabItem("File Drop")
        .tag(Tab.fileDrop)

      FullScreenTab()
        .tabItem("Full Screen")
        .tag(Tab.fullScreen)
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
      name: "Switch to Full Screen",
      action: { selection = .fullScreen }
    )
    .toolbar(style: DefaultBottomToolbarStyle())
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) {
      // Read from the class holder at sheet-content construction
      // time. Because we mutated holder.commands earlier in this
      // same body pass (inside the EnvironmentReader closure), the
      // read here sees the freshest value — not whatever was there
      // before.
      //
      // Query text and focus state are hoisted to this view's
      // storage (see property declarations above for the reason);
      // we pass them through as bindings so the sheet's content can
      // both read and drive them without declaring its own wrappers.
      CommandPaletteList(
        commands: paletteHolder.commands,
        query: $paletteQuery,
        isQueryFocused: $isPaletteQueryFocused,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
    // Nothing to snapshot at this point — the class-backed
    // `paletteHolder.commands` is kept up-to-date continuously by
    // the EnvironmentReader above. Reset the query, ask focus to
    // land on the text field, and flip the sheet open.
    paletteQuery = ""
    isPaletteQueryFocused = true
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
    case fileDrop
    case fullScreen
  }
}
