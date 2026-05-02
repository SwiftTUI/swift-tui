import Foundation
import SwiftTUI

public struct LimitedGalleryView: View {
  public init() {}

  public var body: some View {
    CounterTab()
  }
}

extension LimitedGalleryView {
  enum GalleryTab: Hashable {
    case calculator
  }
}
