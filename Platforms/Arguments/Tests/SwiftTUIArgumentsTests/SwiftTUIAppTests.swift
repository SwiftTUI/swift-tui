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
}

// Test fixtures — declared inside the test target so they don't leak into the
// SwiftTUIArguments product. Both conform to App via a body that returns an empty
// scene (this is just for parsing; we never run the scene in tests).
@MainActor
struct TestSwiftTUIApp: @preconcurrency SwiftTUIApp {
  @OptionGroup public var swiftTUIOptions: SwiftTUIOptions
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
