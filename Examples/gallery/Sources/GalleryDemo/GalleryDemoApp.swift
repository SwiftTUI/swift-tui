import GalleryDemoViews
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
@MainActor
struct GalleryDemoApp: @preconcurrency SwiftTUIApp {
  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }
}
