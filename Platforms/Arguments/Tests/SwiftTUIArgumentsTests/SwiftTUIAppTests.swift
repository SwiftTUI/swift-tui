import Testing
import ArgumentParser
import SwiftTUI
@testable import SwiftTUIArguments

@MainActor
struct SwiftTUIAppTests {
  @Test("SwiftTUIApp parses --no-color and produces expected RuntimeConfiguration")
  func swiftTUIAppParsesNoColor() throws {
    let app = try TestSwiftTUIApp.parse(["--no-color"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.color == .never)
  }

  @Test("SwiftTUIApp parses consumer-defined flag")
  func swiftTUIAppParsesConsumerFlag() throws {
    let app = try TestSwiftTUIApp.parse(["--widgets", "42"])
    #expect(app.widgets == 42)
  }

  @Test("SwiftTUIApp parses both framework and consumer flags")
  func swiftTUIAppParsesBoth() throws {
    let app = try TestSwiftTUIApp.parse(["--widgets", "5", "--accessible"])
    #expect(app.widgets == 5)
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.output == .accessible)
  }

  @Test("Override of runtimeConfiguration() is honored")
  func swiftTUIAppHonorsOverride() throws {
    let app = try TestSwiftTUIAppWithOverride.parse([])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)
    #expect(configuration.debug == true)  // forced on by override
  }

  @Test("--help output includes SWIFTTUI OPTIONS section")
  func helpIncludesSwiftTUIOptionsSection() {
    let helpText = TestSwiftTUIApp.helpMessage()
    #expect(helpText.contains("SWIFTTUI OPTIONS"))
    #expect(helpText.contains("--accessible"))
    #expect(helpText.contains("--no-color"))
    #expect(helpText.contains("--web"))
    // swift-argument-parser may wrap long help strings across lines, so we
    // can't always match `[env: NAME]` as a contiguous substring (e.g. the
    // `--no-color` line wraps `[env: NO_COLOR]` across two lines). Match a
    // shorter, env-label-bearing fragment that fits on one line in practice.
    #expect(helpText.contains("[env: SWIFTTUI_ACCESSIBLE]"))
  }

  // MARK: - Reserved-flag collision detection
  //
  // swift-argument-parser detects duplicate long-flag names across an
  // `AsyncParsableCommand` and any flattened `@OptionGroup`s, but it surfaces
  // the failure via a `fatalError`/`preconditionFailure`-style validation,
  // not a Swift `throws`. That means a consumer redeclaring a reserved
  // SwiftTUI flag (e.g. `@Flag(name: .customLong("accessible"))` alongside
  // `@OptionGroup public var swiftTUIOptions: SwiftTUIOptions`) gets a
  // process-killing diagnostic of the form:
  //
  //     Validation failed for `MyApp`:
  //     - Multiple (2) `Option` or `Flag` arguments are named "--accessible".
  //
  // Swift Testing cannot catch `fatalError`, so this is documented here as a
  // behavior of the underlying parser rather than asserted as a runtime test.
  // The collision IS detected — it just happens before any test code runs.
}

// Test fixtures — declared inside the test target so they don't leak into the
// SwiftTUIArguments product. Both conform to App via a body that returns an empty
// scene (this is just for parsing; we never run the scene in tests).
@MainActor
struct TestSwiftTUIApp: @preconcurrency SwiftTUIApp {
  @OptionGroup(title: "SwiftTUI Options") public var swiftTUIOptions: SwiftTUIOptions
  @Option public var widgets: Int = 10
  init() {}
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
  }
}

@MainActor
struct TestSwiftTUIAppWithOverride: @preconcurrency SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
  init() {}
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
  }
  func runtimeConfiguration(environment: [String: String], isStdoutTTY: Bool)
    -> RuntimeConfiguration
  {
    var c = swiftTUIOptions.runtimeConfiguration(environment: environment, isStdoutTTY: isStdoutTTY)
    c.debug = true
    return c
  }
}

