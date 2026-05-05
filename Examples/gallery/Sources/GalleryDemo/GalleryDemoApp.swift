import ArgumentParser
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

  // `App` (via SwiftTUICLI) and `AsyncParsableCommand` (via SwiftTUIArguments)
  // both supply a default `static func main() async`. Neither is more specific,
  // so a `@main`-marked `SwiftTUIApp` conformer must disambiguate by providing
  // its own `main()` that picks the AsyncParsableCommand path (which parses
  // arguments, then `run()` dispatches into `TerminalRunner.run`).
  static func main() async {
    do {
      var command = try parseAsRoot(nil)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}
