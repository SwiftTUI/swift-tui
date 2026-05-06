import Foundation
import Testing

struct PackageGraphIsolationTests {
  @Test("terminal-only packages do not reference WebHost products")
  func terminalOnlyPackagesDoNotReferenceWebHostProducts() throws {
    let root = repoRoot()
    let rootManifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let cliManifest = try String(
      contentsOf: root.appendingPathComponent("Platforms/CLI/Package.swift"),
      encoding: .utf8
    )

    #expect(!rootManifest.contains("SwiftTUI" + "WebHost"))
    #expect(!cliManifest.contains("SwiftTUI" + "WebHost"))
  }

  @Test("WebHost package contains combined CLI product")
  func webHostPackageContainsCombinedCLIProduct() throws {
    let manifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Platforms/WebHost/Package.swift"),
      encoding: .utf8
    )
    #expect(manifest.contains("SwiftTUIWebHostCLI"))
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
}
