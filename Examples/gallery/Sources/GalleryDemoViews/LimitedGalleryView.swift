import Foundation
import TerminalUI

public struct LimitedGalleryView: View {
  public init() {}

  @State private var selection: GalleryTab = .counter

  public var body: some View {
    TabView(selection: $selection) {
      Tab("Counter", value: GalleryView.GalleryTab.counter) {
        CounterTab()
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

extension LimitedGalleryView {
  enum GalleryTab: Hashable {
    case calculator
  }
}
