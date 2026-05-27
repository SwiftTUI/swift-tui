import Foundation
import Testing

struct PackageGraphIsolationTests {
  @Test("SwiftTUI is the batteries-included convenience product")
  func swiftTUIIsBatteriesIncludedConvenienceProduct() throws {
    let rootManifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let swiftTUITargetBlock = try #require(targetBlock(named: "SwiftTUI", in: rootManifest))

    #expect(swiftTUITargetBlock.contains("\"SwiftTUIWebHostCLI\""))
    #expect(swiftTUITargetBlock.contains("\"SwiftTUIAnimatedImage\""))
    #expect(swiftTUITargetBlock.contains("\"SwiftTUIArguments\""))
    #expect(swiftTUITargetBlock.contains("\"SwiftTUIRuntime\""))
    #expect(!swiftTUITargetBlock.contains("\"SwiftTUICLI\""))
    #expect(!swiftTUITargetBlock.contains("\"SwiftTUICharts\""))
    #expect(!swiftTUITargetBlock.contains("Flying" + "Fox"))
  }

  @Test("SwiftTUIRuntime stays below host and terminal runner products")
  func swiftTUIRuntimeStaysBelowHostAndTerminalRunnerProducts() throws {
    let rootManifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let runtimeTargetBlock = try #require(targetBlock(named: "SwiftTUIRuntime", in: rootManifest))

    #expect(!runtimeTargetBlock.contains("\"SwiftTUICLI\""))
    #expect(!runtimeTargetBlock.contains("SwiftTUI" + "WebHost"))
    #expect(!runtimeTargetBlock.contains("Flying" + "Fox"))
    #expect(!runtimeTargetBlock.contains("Unix" + "Signals"))
    #expect(!runtimeTargetBlock.contains("Swift" + "Term"))
  }

  @Test("argument parser depends below the convenience product")
  func argumentParserDependsBelowConvenienceProduct() throws {
    let rootManifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
    let argumentsTargetBlock = try #require(
      targetBlock(named: "SwiftTUIArguments", in: rootManifest)
    )

    #expect(argumentsTargetBlock.contains("\"SwiftTUIRuntime\""))
    #expect(!argumentsTargetBlock.contains("\"SwiftTUI\""))
  }

  @Test("host products depend on runtime instead of terminal convenience")
  func hostProductsDependOnRuntimeInsteadOfTerminalConvenience() throws {
    let rootManifest = try String(
      contentsOf: repoRoot().appendingPathComponent("Package.swift"),
      encoding: .utf8
    )

    for targetName in [
      "SwiftTUIWebHost",
      "SwiftTUIWASI",
      "WASISurfaceBridge",
      "SwiftUIHost",
      "SwiftTUITerminal",
      "SwiftTUITerminalWorkspace",
    ] {
      let block = try #require(targetBlock(named: targetName, in: rootManifest))
      #expect(block.contains("\"SwiftTUIRuntime\""))
      #expect(!block.contains("\"SwiftTUI\""))
      #expect(!block.contains("\"SwiftTUICLI\""))
    }
  }

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
    let targetStart = ".target("
    var searchRange = manifest.startIndex..<manifest.endIndex

    while let markerRange = manifest.range(of: targetStart, range: searchRange) {
      let suffix = manifest[markerRange.lowerBound...]
      let searchStart = suffix.index(markerRange.lowerBound, offsetBy: targetStart.count)
      let endCandidates = [
        suffix[searchStart...].range(of: "\n    .target(")?.lowerBound,
        suffix[searchStart...].range(of: "\n      .target(")?.lowerBound,
        suffix[searchStart...].range(of: "\n        .target(")?.lowerBound,
        suffix[searchStart...].range(of: "\n    .testTarget(")?.lowerBound,
        suffix[searchStart...].range(of: "\n      .testTarget(")?.lowerBound,
        suffix[searchStart...].range(of: "\n        .testTarget(")?.lowerBound,
      ].compactMap { $0 }

      let blockEnd = endCandidates.min() ?? suffix.endIndex
      let block = String(suffix[..<blockEnd])
      if block.contains("name: \"\(targetName)\"") {
        return block
      }

      searchRange = blockEnd..<manifest.endIndex
    }

    return nil
  }

  private func swiftSources(in directory: URL) throws -> String {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
    else {
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
