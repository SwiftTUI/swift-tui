import GifCat
import SwiftTUI
import SwiftTUICLI
import SwiftTUIArguments

@main
@MainActor
struct GifCatApp: @preconcurrency SwiftTUIApp {
  static let configuration = CommandConfiguration(
    commandName: "gifcat",
    abstract: "Display one or more GIFs in a grid in the terminal."
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions

  @Argument(parsing: .remaining, help: "GIF file paths to display.")
  var paths: [String] = []

  var body: some Scene {
    WindowGroup {
      GifCatView(items: GifCatInput.items(paths: paths))
    }
  }
}
