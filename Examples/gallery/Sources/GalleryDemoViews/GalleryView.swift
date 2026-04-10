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

      AnimationsTab()
        .tabItem("Animations")
        .tag(Tab.animations)
    }
  }
}

extension GalleryView {
  enum Tab: Hashable {
    case counter
    case todo
    case calculator
    case animations
  }
}
