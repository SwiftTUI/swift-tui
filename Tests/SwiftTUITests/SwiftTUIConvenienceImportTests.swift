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
    let app = try ImportSmokeCommand.parse(["--web"])
    let configuration = app.runtimeConfiguration(environment: [:], isStdoutTTY: true)

    #expect(configuration.web != nil)
    #expect(ImportSmokeCommand.configuration.subcommands.count == 1)
  }
}

private struct ImportSmokeCommand: App, SwiftTUICommand {
  @OptionGroup(title: "SwiftTUI Options") public var swiftTUIOptions: SwiftTUIOptions

  init() {}

  var body: some Scene {
    WindowGroup {
      Text("Smoke")
    }
  }
}
