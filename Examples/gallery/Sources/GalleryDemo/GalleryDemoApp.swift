import GalleryDemoViews
import SwiftTUI
import SwiftTUIArguments
import SwiftTUIWebHostCLI

@main
struct GalleryDemoApp: App {
  var body: some Scene {
    WindowGroup {
      GalleryView()
    }
  }

  static func main() async {
    do {
      let options = try GalleryDemoOptions.parse(Array(CommandLine.arguments.dropFirst()))
      try await WebHostCLIRunner.run(
        Self.self,
        configuration: options.swiftTUIOptions.runtimeConfiguration()
      )
    } catch {
      GalleryDemoOptions.exit(withError: error)
    }
  }
}

private struct GalleryDemoOptions: ParsableArguments {
  static let configuration = CommandConfiguration(
    commandName: "gallery-demo",
    abstract: "Explore SwiftTUI controls and runtime behavior."
  )

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions
}
