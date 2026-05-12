import Foundation
import SwiftTUIRuntime

public struct GalleryView: View {
  public init() {}

  // The initial tab honors `GALLERY_INITIAL_TAB` (e.g. "images") so
  // verification scripts and screenshot harnesses can land on a
  // specific tab without driving the command palette.
  @State private var selection: GalleryTab = GalleryView.initialTabFromEnvironment()
  @State private var showPalette: Bool = false

  public var body: some View {
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

      Tab("Text Input", value: GalleryView.GalleryTab.textInput) {
        TextInputTab()
      }

      Tab("Scroll Control", value: GalleryView.GalleryTab.scrollControl) {
        ScrollControlTab()
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

      Tab("Animated GIF", value: GalleryView.GalleryTab.animatedGIF) {
        AnimatedImageTab()
      }

      Tab("Animations", value: GalleryView.GalleryTab.animations) {
        AnimationsTab()
      }

      Tab("File Drop", value: GalleryView.GalleryTab.fileDrop) {
        FileDropTab()
      }

      Tab("Popovers", value: GalleryView.GalleryTab.popovers) {
        PopoverTab()
      }

      Tab("Physics", value: GalleryView.GalleryTab.physics) {
        PhysicsTab()
      }
    }
    .tabViewStyle(.literalTabs)
    .toolbarItem(
      .init(
        title: "⌃K Palette",
        action: { showPalette = true }
      )
    )
    .panel(id: "gallery")
    .keyCommand(
      "Command palette",
      key: .character("k"),
      modifiers: .ctrl,
      action: { showPalette = true }
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
      name: "Text Input",
      action: { selection = .textInput }
    )
    .paletteCommand(
      name: "Scroll Control",
      action: { selection = .scrollControl }
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
      name: "Animated GIF",
      action: { selection = .animatedGIF }
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
      name: "Popovers",
      action: { selection = .popovers }
    )
    .paletteCommand(
      name: "Physics",
      action: { selection = .physics }
    )
    .toolbar(style: .defaultBottom)
    .paletteSheet("Command palette", isPresented: $showPalette) { commands in
      CommandPaletteList(
        commands: commands,
        dismiss: { showPalette = false }
      )
    }
  }
}

extension GalleryView {
  enum GalleryTab: Hashable {
    case life
    case counter
    case todo
    case textInput
    case scrollControl
    case calculator
    case bordersAndShapes
    case images
    case animatedGIF
    case animations
    case fileDrop
    case popovers
    case physics

    init?(environmentName: String) {
      switch environmentName.lowercased() {
      case "life", "conway": self = .life
      case "counter": self = .counter
      case "todo": self = .todo
      case "text", "input", "inputs", "textinput", "text-input", "text-inputs":
        self = .textInput
      case "scroll", "scrollcontrol", "scroll-control", "scrolling":
        self = .scrollControl
      case "calculator", "calc": self = .calculator
      case "borders", "bordersandshapes", "borders-and-shapes", "shapes":
        self = .bordersAndShapes
      case "images", "image": self = .images
      case "animatedgif", "animated-gif", "gif", "animatedimage", "animated-image":
        self = .animatedGIF
      case "animations", "animation": self = .animations
      case "filedrop", "file-drop", "files": self = .fileDrop
      case "popover", "popovers", "tips": self = .popovers
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
