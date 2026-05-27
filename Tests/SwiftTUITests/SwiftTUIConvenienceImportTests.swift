import ArgumentParser
import SwiftTUI
import Testing

struct SwiftTUIConvenienceImportTests {
  @Test("SwiftTUI import exposes WebHost and animated image conveniences")
  func swiftTUIImportExposesWebHostAndAnimatedImageConveniences() {
    _ = WebHostCLIRunner.self
    _ = AnimatedGIF.self
    _ = AnimatedImageFrame(
      width: 1,
      height: 1,
      pixels: [AnimatedImagePixel(red: 0, green: 0, blue: 0)]
    )
  }

  @Test("SwiftTUI import exposes standard argument parsing")
  func swiftTUIImportExposesStandardArgumentParsing() throws {
    let options = try SwiftTUIOptions.parse([
      "--web", "--port", "4567", "--bind", "127.0.0.1", "--open",
    ])
    let configuration = options.runtimeConfiguration(environment: [:], isStdoutTTY: true)

    #expect(configuration.web?.port == 4567)
    #expect(configuration.web?.bind == "127.0.0.1")
    #expect(configuration.web?.openBrowser == true)
  }

  @MainActor
  @Test("SwiftTUI import exposes command conformance surface")
  func swiftTUIImportExposesCommandConformanceSurface() throws {
    let commandType: any SwiftTUICommand.Type = ImportSmokeCommand.self
    #expect(commandType.configuration.subcommands.count == 1)

    let app = try ImportSmokeCommand.parse(["--web", "--widgets", "8"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)

    #expect(app.widgets == 8)
    #expect(configuration.web != nil)
    #expect(ImportSmokeCommand.configuration.subcommands.count == 1)
  }

  @MainActor
  @Test("SwiftTUI App remains source-compatible without stored option group")
  func swiftTUIAppRemainsSourceCompatibleWithoutStoredOptionGroup() {
    let commandType: any SwiftTUICommand.Type = PlainImportSmokeApp.self
    #expect(commandType.configuration.subcommands.count == 1)

    let app = PlainImportSmokeApp()
    #expect(String(describing: type(of: app.body)).contains("WindowGroup"))
  }

  @MainActor
  @Test("SwiftTUI App command parsing uses stored SwiftTUI options when present")
  func swiftTUIAppCommandParsingUsesStoredOptionsWhenPresent() throws {
    let app = try ImportSmokeCommand.parse(["--web", "--port", "4567", "--widgets", "9"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)

    #expect(app.widgets == 9)
    #expect(configuration.web?.port == 4567)
  }

  @Test("Plain SwiftTUI App runtime options still parse through WebHost CLI")
  func plainSwiftTUIAppRuntimeOptionsStillParseThroughWebHostCLI() throws {
    let configuration = try WebHostCLIRunner.runtimeConfiguration(
      arguments: ["--web", "--port", "2468", "--bind", "127.0.0.1"],
      environment: [:],
      isStdoutTTY: true
    )

    #expect(configuration.web?.port == 2468)
    #expect(configuration.web?.bind == "127.0.0.1")
  }
}

private struct ImportSmokeCommand: App {
  @OptionGroup(title: "SwiftTUI Options") public var swiftTUIOptions: SwiftTUIOptions

  @Option(name: .shortAndLong) var widgets: Int = 5

  init() {}

  var body: some Scene {
    WindowGroup {
      Text("Smoke \(widgets)")
    }
  }
}

private struct PlainImportSmokeApp: App {
  init() {}

  var body: some Scene {
    WindowGroup {
      Text("Plain")
    }
  }
}
