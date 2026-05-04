import Foundation
import SwiftTUI

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

  // The initial tab honors `GALLERY_INITIAL_TAB` (e.g. "images") so
  // verification scripts and screenshot harnesses can land on a
  // specific tab without driving the command palette.
  @State private var selection: GalleryTab = GalleryView.initialTabFromEnvironment()
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

      Tab("Life", value: GalleryView.GalleryTab.life) {
        LifeTab()
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
    .paletteCommand(
      name: "Counter",
      action: { selection = .counter }
    )
    .paletteCommand(
      name: "Life",
      action: { selection = .life }
    )
    .paletteCommand(
      name: "Todo",
      action: { selection = .todo }
    )
    .paletteCommand(
      name: "Calculator",
      action: { selection = .calculator }
    )
    .paletteCommand(
      name: "Borders & Shapes",
      action: { selection = .bordersAndShapes }
    )
    .paletteCommand(
      name: "Images",
      action: { selection = .images }
    )
    .paletteCommand(
      name: "Animations",
      action: { selection = .animations }
    )
    .paletteCommand(
      name: "File Drop",
      action: { selection = .fileDrop }
    )
    .paletteCommand(
      name: "Physics",
      action: { selection = .physics }
    )
    .toolbar(style: .defaultBottom)
    .paletteSheet("Command palette", isPresented: $isPaletteOpen) {
      CommandPaletteList(
        commands: paletteHolder.commands,
        dismiss: { isPaletteOpen = false }
      )
    }
  }

  private func openPalette() {
    isPaletteOpen = true
  }
}

extension GalleryView {
  enum GalleryTab: Hashable {
    case life
    case counter
    case todo
    case calculator
    case bordersAndShapes
    case images
    case animations
    case fileDrop
    case physics

    init?(environmentName: String) {
      switch environmentName.lowercased() {
        case "life", "conway": self = .life
      case "counter": self = .counter
      case "todo": self = .todo
      case "calculator", "calc": self = .calculator
      case "borders", "bordersandshapes", "borders-and-shapes", "shapes":
        self = .bordersAndShapes
      case "images", "image": self = .images
      case "animations", "animation": self = .animations
      case "filedrop", "file-drop", "files": self = .fileDrop
      case "physics": self = .physics
      default: return nil
      }
    }
  }

  fileprivate static func initialTabFromEnvironment() -> GalleryTab {
    guard let raw = ProcessInfo.processInfo.environment["GALLERY_INITIAL_TAB"],
      let tab = GalleryTab(environmentName: raw)
    else {
      return .counter
    }
    return tab
  }
}
