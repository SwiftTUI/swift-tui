import SwiftTUI

@main
struct WebHostExampleApp: App {
  init() {}

  var body: some Scene {
    WindowGroup("WebHost Example", id: WindowIdentifier("main")) {
      VStack(alignment: .leading, spacing: 1) {
        Text("SwiftTUI WebHost")
          .bold()
        Divider()
        Text("Terminal and browser output are selected at launch.")
        Text("Run this example with or without --web")
          .foregroundStyle(.red)
      }
      .padding(1)
    }
  }
}
