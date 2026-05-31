import SwiftTUIArguments
import SwiftTUICLI

// Regression fixture for `EntryPointLaunchTests`: the trap form for a
// terminal-native `SwiftTUICommand` (the `SwiftTUICLI` launch layer).
//
// A bare `MyApp.main()` must select the synchronous `main() -> Never`
// diagnostic shim co-located with `extension App where Self: SwiftTUICommand`'s
// async `main()` in `SwiftTUICLI`, not `ParsableCommand.main()`.
struct EntryPointFixtureCLIBare: App, SwiftTUICommand {
  @OptionGroup var swiftTUIOptions: SwiftTUIOptions
  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}

EntryPointFixtureCLIBare.main()
