import SwiftTUI
import SwiftTUIWebHostCLI

@main
@MainActor
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

  static func main() async {
    do {
      try await WebHostCLIRunner.run(Self.self)
    } catch {
      fatalError(String(describing: error))
    }
  }
}
