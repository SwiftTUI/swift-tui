import SwiftTUI

// Regression fixture for `EntryPointLaunchTests`: the trap form.
//
// A bare top-level `MyApp.main()` (no `@main`) resolves to the synchronous
// `main() -> Never` diagnostic shim co-located with `App`'s async `main()`,
// instead of swift-argument-parser's synchronous `ParsableCommand.main()`. The
// launch test asserts the SwiftTUI diagnostic is printed and the process exits
// non-zero — in DEBUG and release alike.
struct EntryPointFixtureBare: App {
  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}

EntryPointFixtureBare.main()
