// Regression coverage for swift-tui issue #6: a `@MainActor` app must stay
// usable as a swift-argument-parser command when the consumer compiles with
// the `ApproachableConcurrency` upcoming feature -- the Swift 6.4
// `swift package init` default. Package.swift compiles this whole test target
// with that feature, so every command fixture in the target is coverage; the
// guard below keeps the setting from being dropped silently.
//
// Without `SwiftTUICommand`'s `nonisolated init(from:)` restatement this file
// (and every other fixture in the target) fails to compile with
//   "main actor-isolated conformance of 'X' to 'Decodable' cannot satisfy
//    conformance requirement for a 'SendableMetatype' type parameter 'Self'"
// so the build itself is the primary assertion. The tests pin the runtime
// behavior the synthesized initializer must keep.

import SwiftTUI
import Testing

#if !hasFeature(InferIsolatedConformances)
  #error(
    "SwiftTUIArgumentsTests must compile with ApproachableConcurrency (InferIsolatedConformances); see Package.swift and swift-tui issue #6."
  )
#endif

@MainActor
struct ApproachableConcurrencyConformanceTests {
  @Test("A plain App with no declared options parses as a root command")
  func plainAppParses() throws {
    _ = try PlainApproachableApp.parse([])
    #expect(PlainApproachableApp.helpMessage().contains("USAGE"))
  }

  @Test("Framework and app options decode through the synthesized init(from:)")
  func optionsAppDecodes() throws {
    let app = try OptionsApproachableApp.parse([
      "--widgets", "5", "--verbose", "alice", "--accessible",
    ])
    #expect(app.widgets == 5)
    #expect(app.verbose)
    #expect(app.name == "alice")
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.motion == .reduced)
  }

  @Test("Declared defaults survive an empty argument list")
  func optionsAppDefaults() throws {
    let app = try OptionsApproachableApp.parse([])
    #expect(app.widgets == 10)
    #expect(!app.verbose)
    #expect(app.name == "n")
  }

  @Test("Parsing works off the main actor: the synthesized init(from:) is nonisolated")
  func parsesOffMainActor() async throws {
    let app = try await Task.detached {
      try OptionsApproachableApp.parse(["--widgets", "3"])
    }.value
    #expect(app.widgets == 3)
  }
}

// Fixtures mirror the consumer shape exactly: `import SwiftTUI` and a bare
// `: App` conformance, with and without declared options.
struct PlainApproachableApp: App {
  init() {}
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
  }
}

struct OptionsApproachableApp: App {
  @OptionGroup(title: "SwiftTUI Options") var swiftTUIOptions: SwiftTUIOptions
  @Option var widgets: Int = 10
  @Flag var verbose = false
  @Argument var name: String = "n"
  init() {}
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
  }
}
