import Foundation
import Testing

struct PackageGraphIsolationTests {
  @Test("terminal-only target does not reference WebHost products")
  func terminalOnlyTargetDoesNotReferenceWebHostProducts() throws {
    let root = repoRoot()
    let rootManifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let cliSources = try swiftSources(in: root.appendingPathComponent("Platforms/CLI/Sources"))
    let cliTargetBlock = try #require(targetBlock(named: "SwiftTUICLI", in: rootManifest))

    #expect(!cliTargetBlock.contains("SwiftTUI" + "WebHost"))
    #expect(!cliTargetBlock.contains("Flying" + "Fox"))
    #expect(!cliSources.contains("SwiftTUI" + "WebHost"))
    #expect(!cliSources.contains("Flying" + "Fox"))
  }

  @Test("root package contains WebHost and combined CLI products")
  func rootPackageContainsWebHostAndCombinedCLIProducts() throws {
    let rootManifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    #expect(rootManifest.contains(".library(name: \"SwiftTUIWebHost\""))
    #expect(rootManifest.contains(".library(name: \"SwiftTUIWebHostCLI\""))
    #expect(rootManifest.contains(".product(name: \"FlyingFox\""))
    #expect(rootManifest.contains(".copy(\"Resources/browser\")"))
  }

  @Test("package-boundary shell guard passes")
  func packageBoundaryShellGuardPasses() throws {
    let root = repoRoot()
    let process = Process()
    process.executableURL = root.appendingPathComponent("Scripts/check_webhost_package_boundary.sh")
    process.currentDirectoryURL = root

    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
  }

  private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func targetBlock(named targetName: String, in manifest: String) -> String? {
    let marker = ".target(\n      name: \"\(targetName)\""
    guard let markerRange = manifest.range(of: marker) else {
      return nil
    }

    let suffix = manifest[markerRange.lowerBound...]
    if let nextTarget = suffix.dropFirst(marker.count).range(of: "\n    .target(") {
      return String(suffix[..<nextTarget.lowerBound])
    }
    if let nextTestTarget = suffix.dropFirst(marker.count).range(of: "\n    .testTarget(") {
      return String(suffix[..<nextTestTarget.lowerBound])
    }
    return String(suffix)
  }

  private func swiftSources(in directory: URL) throws -> String {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
      return ""
    }

    var contents = ""
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      contents += try String(contentsOf: fileURL, encoding: .utf8)
      contents += "\n"
    }
    return contents
  }
}
