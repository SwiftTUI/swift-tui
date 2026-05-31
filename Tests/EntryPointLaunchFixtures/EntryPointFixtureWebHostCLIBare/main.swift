import SwiftTUIArguments
import SwiftTUIWebHostCLI

// Regression fixture for `EntryPointLaunchTests`: the trap form for a
// terminal/WebHost `SwiftTUICommand` (the `SwiftTUIWebHostCLI` launch layer).
//
// A bare `MyApp.main()` must select the synchronous `main() -> Never`
// diagnostic shim co-located with `extension App where Self: SwiftTUICommand`'s
// async `main()` in `SwiftTUIWebHostCLI`, not `ParsableCommand.main()`.
struct EntryPointFixtureWebHostCLIBare: App, SwiftTUICommand {
  @OptionGroup var swiftTUIOptions: SwiftTUIOptions
  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}

EntryPointFixtureWebHostCLIBare.main()
