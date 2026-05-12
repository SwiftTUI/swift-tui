import Foundation
import Testing

struct GalleryWebHostCompositionTests {
  @Test("gallery executable imports the WebHost runner without direct terminal CLI ownership")
  func galleryExecutableImportsWebHostRunnerWithoutDirectTerminalCLIOwnership() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let source = try String(
      contentsOf: packageRoot.appendingPathComponent("Sources/GalleryDemo/GalleryDemoApp.swift"),
      encoding: .utf8
    )
    let manifest = try String(
      contentsOf: packageRoot.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )

    #expect(source.contains("import SwiftTUIWebHostCLI"))
    #expect(source.contains("WebHostCLIRunner.run("))
    #expect(source.contains("struct GalleryDemoOptions: ParsableArguments"))
    #expect(!source.contains("import SwiftTUI\n"))
    #expect(!source.contains("import SwiftTUICLI"))

    #expect(manifest.contains("SwiftTUIWebHostCLI"))
    #expect(!manifest.contains("SwiftTUIArguments"))
    #expect(!manifest.contains("SwiftTUICLI"))
  }
}
