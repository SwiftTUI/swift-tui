import TerminalUI

public struct GalleryView: View {
  public init() {}

  @State private var selection: Tab = .counter

  public var body: some View {
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

      AnimationsTab()
        .tabItem("Animations")
        .tag(Tab.animations)
    }
    .tabViewStyle(.powerline)
  }
}

extension GalleryView {
  enum Tab: Hashable {
    case counter
    case todo
    case calculator
    case bordersAndShapes
    case animations
  }
}
