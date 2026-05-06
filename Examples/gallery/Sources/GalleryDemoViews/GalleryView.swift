import Foundation
import SwiftTUI

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
    .paletteSheet("Open...", isPresented: $showPalette, content: { Text("...") })
  }
}

extension GalleryView {
  enum GalleryTab: Hashable {
    case life
    case counter
    case todo
    case textInput
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
      case "text", "input", "inputs", "textinput", "text-input", "text-inputs":
        self = .textInput
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
