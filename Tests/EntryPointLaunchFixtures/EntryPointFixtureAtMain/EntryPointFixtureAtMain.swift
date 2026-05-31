import SwiftTUI

// Regression fixture for `EntryPointLaunchTests`: the supported launch form.
//
// `@main` binds `App`'s asynchronous entry point, so running this binary starts
// the runtime and renders a frame containing the `ENTRYPOINTOK` marker. The
// launch test asserts the marker appears and that no synchronous-launch
// diagnostic (or swift-argument-parser availability message) is printed.
@main
struct EntryPointFixtureAtMain: App {
  var body: some Scene {
    WindowGroup {
      Text("ENTRYPOINTOK")
    }
  }
}
