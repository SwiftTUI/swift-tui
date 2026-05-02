import Foundation
import TerminalUI

public struct LimitedGalleryView: View {
  public init() {}

  @State private var selection: GalleryTab = .counter

  public var body: some View {
    TabView(selection: $selection) {
      Tab("Play Ball", value: GalleryView.GalleryTab.physics) {
        PhysicsTab()
      }

      Tab("Counter", value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }

      Tab("Calculator", value: GalleryView.GalleryTab.calculator) {
        CalculatorTab()
      }

      Tab("Animations", value: GalleryView.GalleryTab.animations) {
        AnimationsTab()
      }

    }
    .tabViewStyle(.literalTabs)
  }
}

extension LimitedGalleryView {
  enum GalleryTab: Hashable {
    case counter
    case calculator
    case animations
    case physics
  }
}
